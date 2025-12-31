// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PoidhV3} from "../src/PoidhV3.sol";
import {PoidhClaimNFT} from "../src/PoidhClaimNFT.sol";

/// @title PoidhV3 Economic Griefing & Edge Case Tests
/// @notice Tests for non-exploit attack vectors: griefing, MEV, admin abuse, config footguns
/// @dev These tests document KNOWN LIMITATIONS and potential improvements

// ============================================================================
// HELPER CONTRACTS
// ============================================================================

/// @notice Contract that reverts on ETH receive - causes withdraw to fail
contract RevertingReceiver {
  PoidhV3 public poidh;

  constructor(address _poidh) {
    poidh = PoidhV3(payable(_poidh));
  }

  function createClaim(uint256 bountyId) external {
    poidh.createClaim(bountyId, "claim", "desc", "ipfs://x");
  }

  function withdraw() external {
    poidh.withdraw();
  }

  function withdrawTo(address payable to) external {
    poidh.withdrawTo(to);
  }

  // Revert on any ETH received
  receive() external payable {
    revert("I don't accept ETH");
  }
}

/// @notice Contract that accepts ETH but can't transfer NFTs
contract NFTSinkContract {
  // No onERC721Received, but can still receive via transferFrom
  receive() external payable {}
}

/// @notice Contract that creates bounties (issuer is a contract)
contract ContractIssuer {
  PoidhV3 public poidh;

  constructor(address _poidh) {
    poidh = PoidhV3(payable(_poidh));
  }

  function createSoloBounty() external payable returns (uint256) {
    poidh.createSoloBounty{value: msg.value}("Contract Bounty", "Desc");
    return poidh.bountyCounter() - 1;
  }

  function acceptClaim(uint256 bountyId, uint256 claimId) external {
    poidh.acceptClaim(bountyId, claimId);
  }

  function withdraw() external {
    poidh.withdraw();
  }

  receive() external payable {}
}

// ============================================================================
// MAIN TEST CONTRACT
// ============================================================================
contract PoidhV3GriefingTest is Test {
  PoidhV3 public poidh;
  PoidhClaimNFT public nft;

  address public treasury;
  address public issuer;
  address public claimant;

  function setUp() public {
    treasury = makeAddr("treasury");
    issuer = makeAddr("issuer");
    claimant = makeAddr("claimant");

    vm.deal(issuer, 100 ether);
    vm.deal(claimant, 100 ether);

    nft = new PoidhClaimNFT("poidh claims v3", "POIDH3");
    poidh = new PoidhV3(address(nft), treasury, 1);
    nft.setPoidh(address(poidh));
  }

  // ========================================================================
  // 1. ECONOMIC GRIEFING - Dust Join Forces Voting
  // ========================================================================
  function test_GRIEFING_minContribution_forces_voting() public {
    // Issuer creates open bounty
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 10 ether}("Big Bounty", "Description");
    uint256 bountyId = 0;

    // Griefer joins with just MIN_CONTRIBUTION - this is the minimum allowed amount
    address griefer = makeAddr("griefer");
    uint256 minContrib = poidh.MIN_CONTRIBUTION();
    vm.deal(griefer, minContrib);
    vm.prank(griefer);
    poidh.joinOpenBounty{value: minContrib}(bountyId);

    // Now everHadExternalContributor is TRUE
    assertTrue(poidh.everHadExternalContributor(bountyId), "Flag should be set");

    // Even if griefer withdraws...
    vm.prank(griefer);
    poidh.withdrawFromOpenBounty(bountyId);

    // Flag is STILL true - issuer is permanently forced into voting
    assertTrue(poidh.everHadExternalContributor(bountyId), "Flag persists after withdrawal");

    // Issuer creates a claim
    vm.prank(claimant);
    poidh.createClaim(bountyId, "Claim", "Desc", "ipfs://x");

    // Direct accept should fail
    vm.prank(issuer);
    vm.expectRevert(PoidhV3.NotSoloBounty.selector);
    poidh.acceptClaim(bountyId, 1);
  }

  // ========================================================================
  // 2. ECONOMIC GRIEFING - Last-Second Join Before Vote
  // ========================================================================
  function test_GRIEFING_join_before_vote_frontrun() public {
    // Setup
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("Bounty", "Description");
    uint256 bountyId = 0;

    vm.prank(claimant);
    poidh.createClaim(bountyId, "Claim", "Desc", "ipfs://x");

    // Attacker sees submitClaimForVote in mempool and frontruns with join
    address attacker = makeAddr("attacker");
    vm.deal(attacker, 10 ether);

    // Attacker joins BEFORE vote starts (in same block, earlier tx)
    vm.prank(attacker);
    poidh.joinOpenBounty{value: 5 ether}(bountyId);

    // Now issuer submits vote - attacker already in with 5 ETH
    vm.prank(issuer);
    poidh.submitClaimForVote(bountyId, 1);

    // Attacker has more weight than issuer (5 ETH vs 1 ETH)
    // Attacker votes NO
    vm.prank(attacker);
    poidh.voteClaim(bountyId, false);

    // Check vote state
    (uint256 yes, uint256 no,) = poidh.bountyVotingTracker(bountyId);
    assertEq(yes, 1 ether, "Issuer YES weight");
    assertEq(no, 5 ether, "Attacker NO weight");

    // Vote will fail because NO > YES
    vm.warp(block.timestamp + 2 days + 1);
    poidh.resolveVote(bountyId);

    // Bounty not accepted
    (,,,,, address claimer,,) = poidh.bounties(bountyId);
    assertEq(claimer, address(0), "Bounty should not be claimed");
  }

  // ========================================================================
  // 4. NO PAUSE - Contract is not pausable (by design)
  // ========================================================================
  function test_NO_PAUSE_contract_not_pausable() public {
    // Verify the contract is not pausable - no admin can freeze operations
    // This was a deliberate design decision to prevent admin abuse

    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: 1 ether}("Bounty", "Description");

    vm.prank(issuer);
    poidh.cancelSoloBounty(0);

    assertEq(poidh.pendingWithdrawals(issuer), 1 ether);

    // Withdraw works normally - no pause mechanism exists
    uint256 balBefore = issuer.balance;
    vm.prank(issuer);
    poidh.withdraw();

    assertEq(poidh.pendingWithdrawals(issuer), 0);
    assertEq(issuer.balance, balBefore + 1 ether);
  }

  // ========================================================================
  // 5. CONFIG FOOTGUN - Wrong Treasury Address
  // ========================================================================
  function test_FOOTGUN_wrong_treasury_permanent_loss() public {
    // Deploy with wrong treasury (e.g., zero address blocked, but typo address isn't)
    address wrongTreasury = address(0xdead);

    PoidhClaimNFT newNft = new PoidhClaimNFT("test", "TEST");
    PoidhV3 badPoidh = new PoidhV3(address(newNft), wrongTreasury, 1);
    newNft.setPoidh(address(badPoidh));

    // Fees will go to wrong address forever (immutable)
    assertEq(badPoidh.treasury(), wrongTreasury);
  }

  // ========================================================================
  // 6. NFT SINK - Contract Issuer Can't Move NFT
  // ========================================================================
  function test_EDGE_CASE_contracts_cannot_create_bounties() public {
    // Deploy a contract that would try to create bounties
    ContractIssuer contractIssuer = new ContractIssuer(address(poidh));
    vm.deal(address(contractIssuer), 10 ether);

    // Contract cannot create bounty - blocked by ContractsCannotCreateBounties check
    vm.expectRevert(PoidhV3.ContractsCannotCreateBounties.selector);
    contractIssuer.createSoloBounty{value: 1 ether}();
  }

  // ========================================================================
  // 7. DOS - Claim Spam / Storage Bloat
  // ========================================================================
  function test_DOS_claim_spam() public {
    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: 1 ether}("Bounty", "Description");

    // Spammer creates many claims - only costs gas
    address spammer = makeAddr("spammer");
    uint256 spamCount = 25;

    for (uint256 i = 0; i < spamCount; i++) {
      vm.prank(spammer);
      poidh.createClaim(0, "SPAM SPAM SPAM SPAM SPAM", "SPAM SPAM SPAM", "ipfs://spam");
    }

    assertEq(poidh.claimCounter(), spamCount + 1); // claimId 0 reserved sentinel
  }

  // ========================================================================
  // 8. DOS - Participant Slot Exhaustion
  // ========================================================================
  function test_DOS_participant_slot_exhaustion() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("Bounty", "Description");

    uint256 maxParticipants = poidh.MAX_PARTICIPANTS();
    uint256 minContrib = poidh.MIN_CONTRIBUTION();

    // Attacker fills all participant slots with minimum contribution
    for (uint256 i = 1; i < maxParticipants; i++) {
      address attacker = vm.addr(i + 5000);
      vm.deal(attacker, 1 ether);
      vm.prank(attacker);
      poidh.joinOpenBounty{value: minContrib}(0);
    }

    // Legitimate user cannot join
    address legitUser = makeAddr("legit");
    vm.deal(legitUser, 10 ether);
    vm.prank(legitUser);
    vm.expectRevert(PoidhV3.MaxParticipantsReached.selector);
    poidh.joinOpenBounty{value: 5 ether}(0);
  }

  // ========================================================================
  // 9. SELF-DOS - Receiver Revert on Withdraw
  // ========================================================================
  function test_SELF_DOS_receiver_revert() public {
    // Deploy reverting receiver
    RevertingReceiver badReceiver = new RevertingReceiver(address(poidh));

    // EOA creates bounty
    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: 1 ether}("Test", "Desc");

    // Bad receiver submits a claim
    badReceiver.createClaim(0);

    // Issuer accepts the claim - now badReceiver has pending withdrawals
    vm.prank(issuer);
    poidh.acceptClaim(0, 1);

    // Funds are pending (minus fee)
    uint256 expectedPayout = 1 ether - (1 ether * poidh.FEE_BPS() / poidh.BPS_DENOM());
    assertEq(poidh.pendingWithdrawals(address(badReceiver)), expectedPayout);

    // But withdraw fails because receiver reverts
    vm.expectRevert(PoidhV3.TransferFailed.selector);
    badReceiver.withdraw();

    // Funds still pending
    assertEq(poidh.pendingWithdrawals(address(badReceiver)), expectedPayout);

    // BUT! They can use withdrawTo to send to a different address
    address rescueAddr = makeAddr("rescueAddr");
    badReceiver.withdrawTo(payable(rescueAddr));

    // Now funds are rescued
    assertEq(poidh.pendingWithdrawals(address(badReceiver)), 0);
    assertEq(rescueAddr.balance, expectedPayout);
  }

  // ========================================================================
  // 10. MEV - Vote Resolution Timing
  // ========================================================================
  function test_MEV_vote_resolution_timing() public {
    // Setup voting
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("Bounty", "Description");

    address contributor = makeAddr("contributor");
    vm.deal(contributor, 1 ether);
    vm.prank(contributor);
    poidh.joinOpenBounty{value: 0.5 ether}(0);

    vm.prank(claimant);
    poidh.createClaim(0, "Claim", "Desc", "ipfs://x");

    vm.prank(issuer);
    poidh.submitClaimForVote(0, 1);

    // Contributor votes NO
    vm.prank(contributor);
    poidh.voteClaim(0, false);

    // Fast forward to exactly deadline
    vm.warp(block.timestamp + 2 days);

    // Anyone can resolve immediately - MEV bot opportunity
    address mevBot = makeAddr("mevBot");
    vm.prank(mevBot);
    poidh.resolveVote(0);
  }

  // ========================================================================
  // 11. EDGE CASE - Issuer withdraws ALL, bounty has 0 amount
  // ========================================================================
  function test_EDGE_CASE_issuer_contribution_matters() public {
    // Create open bounty
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("Bounty", "Description");

    // Add contributor
    address contributor = makeAddr("contributor");
    vm.deal(contributor, 1 ether);
    vm.prank(contributor);
    poidh.joinOpenBounty{value: 0.5 ether}(0);

    // Issuer cannot withdraw (by design)
    vm.prank(issuer);
    vm.expectRevert(PoidhV3.IssuerCannotWithdraw.selector);
    poidh.withdrawFromOpenBounty(0);
  }

  // ========================================================================
  // 12. EDGE CASE - Vote with withdrawn weight still tracked
  // ========================================================================
  function test_EDGE_CASE_vote_weight_after_withdraw() public {
    // Setup
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("Bounty", "Description");

    address contributor = makeAddr("contributor");
    vm.deal(contributor, 1 ether);
    vm.prank(contributor);
    poidh.joinOpenBounty{value: 0.5 ether}(0);

    // Contributor withdraws BEFORE voting starts
    vm.prank(contributor);
    poidh.withdrawFromOpenBounty(0);

    // Start voting
    vm.prank(claimant);
    poidh.createClaim(0, "Claim", "Desc", "ipfs://x");

    vm.prank(issuer);
    poidh.submitClaimForVote(0, 1);

    // Contributor tries to vote - should fail (no weight)
    vm.prank(contributor);
    vm.expectRevert(PoidhV3.NotActiveParticipant.selector);
    poidh.voteClaim(0, true);
  }

  // ========================================================================
  // 13. EDGE CASE - Multiple claims, accept specific one
  // ========================================================================
  function test_EDGE_CASE_multiple_claims_accept_any() public {
    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: 1 ether}("Bounty", "Description");

    // Multiple claimants
    address claimant1 = makeAddr("claimant1");
    address claimant2 = makeAddr("claimant2");
    address claimant3 = makeAddr("claimant3");

    vm.prank(claimant1);
    poidh.createClaim(0, "Claim1", "Desc", "ipfs://1");

    vm.prank(claimant2);
    poidh.createClaim(0, "Claim2", "Desc", "ipfs://2");

    vm.prank(claimant3);
    poidh.createClaim(0, "Claim3", "Desc", "ipfs://3");

    // Issuer can accept any claim (e.g., claim 2)
    vm.prank(issuer);
    poidh.acceptClaim(0, 2);

    // Claimant2 gets payout
    uint256 expectedPayout = 1 ether - (1 ether * 250) / 10_000;
    assertEq(poidh.pendingWithdrawals(claimant2), expectedPayout);

    // Other claimants get nothing
    assertEq(poidh.pendingWithdrawals(claimant1), 0);
    assertEq(poidh.pendingWithdrawals(claimant3), 0);
  }
}
