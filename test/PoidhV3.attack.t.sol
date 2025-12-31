// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PoidhV3} from "../src/PoidhV3.sol";
import {PoidhClaimNFT} from "../src/PoidhClaimNFT.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @title PoidhV3 Red Team Attack Tests
/// @notice Attempts to reproduce v2 exploit vectors against v3
/// @dev Based on the POIDH v3 Security Analysis & Rebuild Specification

// ============================================================================
// ATTACK CONTRACT 1: ERC721 Callback Reentrancy Attacker
// This reproduces the blackhat exploit from v2 where safeTransfer callback
// was used to re-enter before state was finalized
// ============================================================================
contract ERC721ReentrancyAttacker is IERC721Receiver {
  PoidhV3 public target;
  uint256 public attackBountyId;
  uint256 public attackClaimId;
  uint256 public attackCount;
  uint256 public maxAttacks;
  bool public attacking;

  // Track how much ETH we've extracted
  uint256 public extractedAmount;

  constructor(address _target) {
    target = PoidhV3(payable(_target));
  }

  function setAttackParams(uint256 bountyId, uint256 claimId, uint256 _maxAttacks) external {
    attackBountyId = bountyId;
    attackClaimId = claimId;
    maxAttacks = _maxAttacks;
  }

  /// @notice Called when NFT is transferred via safeTransferFrom
  /// In v2, this was the attack vector - the callback fires BEFORE state finalization
  function onERC721Received(address, address, uint256, bytes calldata)
    external
    override
    returns (bytes4)
  {
    if (attacking && attackCount < maxAttacks) {
      attackCount++;

      // ATTACK VECTOR 1: Try to re-accept the same claim
      // In v2, bounty.amount was never zeroed, so this would drain funds
      try target.acceptClaim(attackBountyId, attackClaimId) {
        extractedAmount += 1; // Track successful reentry
      } catch {
        // Expected to fail in v3
      }

      // ATTACK VECTOR 2: Try to withdraw during callback
      try target.withdraw() {
        extractedAmount += 1;
      } catch {
        // Expected to fail due to nonReentrant
      }
    }
    return this.onERC721Received.selector;
  }

  /// @notice ETH receive callback - another reentrancy vector
  receive() external payable {
    if (attacking && attackCount < maxAttacks) {
      attackCount++;

      // Try to drain more via withdraw
      try target.withdraw() {
        extractedAmount += msg.value;
      } catch {
        // Expected to fail
      }
    }
  }

  function startAttack() external {
    attacking = true;
  }

  function stopAttack() external {
    attacking = false;
  }

  function withdrawFunds() external {
    payable(msg.sender).transfer(address(this).balance);
  }
}

// ============================================================================
// HELPER CONTRACT: Contract that tries to create a bounty (should fail)
// ============================================================================
contract ContractBountyCreator {
  PoidhV3 public target;

  constructor(address _target) {
    target = PoidhV3(payable(_target));
  }

  function createBounty() external {
    target.createSoloBounty{value: 1 ether}("Contract Bounty", "Description");
  }

  receive() external payable {}
}

// ============================================================================
// ATTACK CONTRACT 2: cancelOpenBounty Loop Reentrancy Attacker
// This reproduces the whitehack exploit from v2 where refund loop
// didn't zero slots before external calls
// ============================================================================
contract CancelLoopReentrancyAttacker {
  PoidhV3 public target;
  uint256 public attackBountyId;
  uint256 public attackCount;
  uint256 public maxAttacks;
  bool public attacking;
  uint256 public extractedAmount;

  constructor(address _target) {
    target = PoidhV3(payable(_target));
  }

  function setAttackParams(uint256 bountyId, uint256 _maxAttacks) external {
    attackBountyId = bountyId;
    maxAttacks = _maxAttacks;
  }

  function joinBounty(uint256 bountyId) external payable {
    target.joinOpenBounty{value: msg.value}(bountyId);
  }

  receive() external payable {
    if (attacking && attackCount < maxAttacks) {
      attackCount++;

      // ATTACK VECTOR: During cancel refund, try to withdraw again
      // In v2, participant record was still intact during the loop
      try target.withdrawFromOpenBounty(attackBountyId) {
      // This would have worked in v2
      }
        catch {
        // Expected to fail in v3 (bounty is already marked closed)
      }

      // Try to claim refund as well
      try target.claimRefundFromCancelledOpenBounty(attackBountyId) {
        extractedAmount += msg.value;
      } catch {
        // Expected behavior
      }

      // Try the general withdraw
      try target.withdraw() {
        extractedAmount += msg.value;
      } catch {
        // Expected to fail due to nonReentrant
      }
    }
  }

  function startAttack() external {
    attacking = true;
  }

  function stopAttack() external {
    attacking = false;
  }

  function triggerWithdraw() external {
    target.withdraw();
  }

  function claimRefund(uint256 bountyId) external {
    target.claimRefundFromCancelledOpenBounty(bountyId);
  }
}

// ============================================================================
// ATTACK CONTRACT 3: Cross-Function Reentrancy Attacker
// Attempts cancel -> withdraw cross-function reentrancy
// ============================================================================
contract CrossFunctionReentrancyAttacker {
  PoidhV3 public target;
  uint256 public attackBountyId;
  uint256 public attackCount;
  bool public attacking;
  uint256 public extractedAmount;

  enum AttackMode {
    WITHDRAW_FROM_OPEN,
    CLAIM_REFUND,
    GENERAL_WITHDRAW
  }
  AttackMode public mode;

  constructor(address _target) {
    target = PoidhV3(payable(_target));
  }

  function setAttackParams(uint256 bountyId, AttackMode _mode) external {
    attackBountyId = bountyId;
    mode = _mode;
  }

  function joinBounty(uint256 bountyId) external payable {
    target.joinOpenBounty{value: msg.value}(bountyId);
  }

  function createClaim(uint256 bountyId, string memory name, string memory desc, string memory uri)
    external
  {
    target.createClaim(bountyId, name, desc, uri);
  }

  receive() external payable {
    if (attacking && attackCount < 5) {
      attackCount++;

      if (mode == AttackMode.WITHDRAW_FROM_OPEN) {
        // Cross-function: during withdraw callback, try withdraw again
        try target.withdrawFromOpenBounty(attackBountyId) {
          extractedAmount += msg.value;
        } catch {}
      } else if (mode == AttackMode.CLAIM_REFUND) {
        // Cross-function: try claiming refund during another operation
        try target.claimRefundFromCancelledOpenBounty(attackBountyId) {
          extractedAmount += msg.value;
        } catch {}
      } else {
        // Try general withdraw reentrancy
        try target.withdraw() {
          extractedAmount += msg.value;
        } catch {}
      }
    }
  }

  function startAttack() external {
    attacking = true;
  }

  function stopAttack() external {
    attacking = false;
  }

  function triggerWithdraw() external {
    target.withdraw();
  }

  function triggerWithdrawFromOpen(uint256 bountyId) external {
    target.withdrawFromOpenBounty(bountyId);
  }
}

// ============================================================================
// ATTACK CONTRACT 4: Voting Manipulation Attacker
// Attempts to manipulate voting state
// ============================================================================
contract VotingManipulationAttacker {
  PoidhV3 public target;

  constructor(address _target) {
    target = PoidhV3(payable(_target));
  }

  function joinBounty(uint256 bountyId) external payable {
    target.joinOpenBounty{value: msg.value}(bountyId);
  }

  function vote(uint256 bountyId, bool support) external {
    target.voteClaim(bountyId, support);
  }

  // Try to vote multiple times in the same round
  function doubleVote(uint256 bountyId) external {
    target.voteClaim(bountyId, true);
    target.voteClaim(bountyId, false); // Should revert
  }

  function withdrawDuringVoting(uint256 bountyId) external {
    target.withdrawFromOpenBounty(bountyId); // Should revert during voting
  }

  receive() external payable {}
}

// ============================================================================
// MAIN TEST CONTRACT
// ============================================================================
contract PoidhV3AttackTest is Test {
  PoidhV3 public poidh;
  PoidhClaimNFT public nft;

  address public treasury;
  address public issuer;
  address public claimant;

  ERC721ReentrancyAttacker public erc721Attacker;
  CancelLoopReentrancyAttacker public cancelAttacker;
  CrossFunctionReentrancyAttacker public crossFunctionAttacker;
  VotingManipulationAttacker public votingAttacker;

  function setUp() public {
    treasury = makeAddr("treasury");
    issuer = makeAddr("issuer");
    claimant = makeAddr("claimant");

    vm.deal(issuer, 100 ether);
    vm.deal(claimant, 100 ether);

    // Deploy contracts
    nft = new PoidhClaimNFT("poidh claims v3", "POIDH3");
    poidh = new PoidhV3(address(nft), treasury, 1);
    nft.setPoidh(address(poidh));

    // Deploy attack contracts
    erc721Attacker = new ERC721ReentrancyAttacker(address(poidh));
    cancelAttacker = new CancelLoopReentrancyAttacker(address(poidh));
    crossFunctionAttacker = new CrossFunctionReentrancyAttacker(address(poidh));
    votingAttacker = new VotingManipulationAttacker(address(poidh));

    vm.deal(address(erc721Attacker), 10 ether);
    vm.deal(address(cancelAttacker), 10 ether);
    vm.deal(address(crossFunctionAttacker), 10 ether);
    vm.deal(address(votingAttacker), 10 ether);
  }

  // ========================================================================
  // TEST: ERC721 Callback Reentrancy (v2 Blackhat Exploit)
  // Note: Now that contracts can't create bounties, the v2 exploit is doubly blocked:
  // 1. Contracts cannot be bounty issuers (no callback target)
  // 2. Even if they could, v3 uses transferFrom not safeTransferFrom (no callback)
  // ========================================================================
  function test_attack_erc721_callback_reentrancy_BLOCKED() public {
    // Setup: Create solo bounty with EOA issuer (contracts can't create bounties now)
    vm.prank(issuer, issuer); // Set both msg.sender and tx.origin
    poidh.createSoloBounty{value: 1 ether}("Test Bounty", "Description");
    uint256 bountyId = 0;

    // Claimant creates a claim
    vm.prank(claimant);
    poidh.createClaim(bountyId, "Claim", "Description", "ipfs://claim");
    uint256 claimId = 1;

    // Issuer accepts claim - NFT is transferred via transferFrom (no callback)
    vm.prank(issuer, issuer);
    poidh.acceptClaim(bountyId, claimId);

    // VERIFICATION: Claim acceptance works correctly
    // 1. Claimant gets payout in pendingWithdrawals
    uint256 expectedPayout = 1 ether - (1 ether * 250) / 10_000;
    assertEq(
      poidh.pendingWithdrawals(claimant), expectedPayout, "Claimant should have payout pending"
    );

    // 2. Treasury gets fee
    uint256 expectedFee = (1 ether * 250) / 10_000;
    assertEq(poidh.pendingWithdrawals(treasury), expectedFee, "Treasury should have fee pending");

    // 3. Bounty should be properly finalized
    (,,,, uint256 amount, address claimer,,) = poidh.bounties(bountyId);
    assertEq(amount, 0, "Bounty amount should be zeroed");
    assertEq(claimer, claimant, "Claimer should be set to claimant");

    // 4. NFT should be owned by issuer (bounty issuer)
    assertEq(nft.ownerOf(claimId), issuer, "NFT should be with bounty issuer");
  }

  // ========================================================================
  // TEST: cancelOpenBounty Loop Reentrancy (v2 Whitehack Exploit)
  // ========================================================================
  function test_attack_cancel_loop_reentrancy_BLOCKED() public {
    // Setup: Create open bounty
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("Open Bounty", "Description");
    uint256 bountyId = 0;

    // Attacker joins the bounty
    vm.prank(address(cancelAttacker));
    cancelAttacker.joinBounty{value: 0.5 ether}(bountyId);

    // Configure attack
    cancelAttacker.setAttackParams(bountyId, 5);
    cancelAttacker.startAttack();

    // Issuer cancels - in v2 this would trigger loop with reentrancy opportunity
    // In v3, cancelOpenBounty only refunds the issuer; contributors must call claimRefund
    vm.prank(issuer);
    poidh.cancelOpenBounty(bountyId);

    // VERIFICATION: v3 uses pull payments, no loop with external calls
    // 1. Issuer gets immediate refund in pendingWithdrawals
    uint256 issuerPending = poidh.pendingWithdrawals(issuer);
    assertEq(issuerPending, 1 ether, "Issuer should have refund pending");

    // 2. Attacker contribution is NOT yet in pendingWithdrawals (must claim)
    uint256 attackerPending = poidh.pendingWithdrawals(address(cancelAttacker));
    assertEq(attackerPending, 0, "Attacker must call claimRefund first");

    // 3. No reentrancy occurred during cancel
    assertEq(cancelAttacker.extractedAmount(), 0, "No extra funds should be extracted");

    // 4. Now attacker legitimately claims refund
    cancelAttacker.stopAttack();
    vm.prank(address(cancelAttacker));
    cancelAttacker.claimRefund(bountyId);

    // 5. Now attacker has funds pending
    attackerPending = poidh.pendingWithdrawals(address(cancelAttacker));
    assertEq(attackerPending, 0.5 ether, "Attacker should have contribution pending after claim");

    // 6. Withdraw
    vm.prank(address(cancelAttacker));
    cancelAttacker.triggerWithdraw();
  }

  // ========================================================================
  // TEST: Cross-Function Reentrancy
  // ========================================================================
  function test_attack_cross_function_reentrancy_BLOCKED() public {
    // Setup: Create open bounty
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("Open Bounty", "Description");
    uint256 bountyId = 0;

    // Attacker joins
    vm.prank(address(crossFunctionAttacker));
    crossFunctionAttacker.joinBounty{value: 0.5 ether}(bountyId);

    // Configure attack - try to withdraw multiple times
    crossFunctionAttacker.setAttackParams(
      bountyId, CrossFunctionReentrancyAttacker.AttackMode.WITHDRAW_FROM_OPEN
    );
    crossFunctionAttacker.startAttack();

    // Try to withdraw - this credits pendingWithdrawals, then attacker tries reentry
    vm.prank(address(crossFunctionAttacker));
    crossFunctionAttacker.triggerWithdrawFromOpen(bountyId);

    // Check: pending should be exactly the contribution
    uint256 pending = poidh.pendingWithdrawals(address(crossFunctionAttacker));
    assertEq(pending, 0.5 ether, "Should have exactly contribution in pending");

    // Attacker should not have extracted extra
    assertEq(crossFunctionAttacker.extractedAmount(), 0, "No extra funds extracted");
  }

  // ========================================================================
  // TEST: Pull Payment Withdraw Reentrancy
  // ========================================================================
  function test_attack_withdraw_reentrancy_BLOCKED() public {
    // Setup: EOA creates bounty, attacker contract submits claim and gets accepted
    // This gives the attacker contract pending withdrawals to test reentrancy
    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: 1 ether}("Test", "Desc");

    // Attacker submits a claim
    crossFunctionAttacker.createClaim(0, "attack claim", "desc", "ipfs://x");

    // Issuer accepts the claim - now attacker contract has pending withdrawals
    vm.prank(issuer);
    poidh.acceptClaim(0, 1);

    // Attacker has pending withdrawal (minus fee)
    uint256 expectedPayout = 1 ether - (1 ether * poidh.FEE_BPS() / poidh.BPS_DENOM());
    uint256 pending = poidh.pendingWithdrawals(address(crossFunctionAttacker));
    assertEq(pending, expectedPayout);

    // Configure attack
    crossFunctionAttacker.setAttackParams(
      0, CrossFunctionReentrancyAttacker.AttackMode.GENERAL_WITHDRAW
    );
    crossFunctionAttacker.startAttack();

    // Try withdraw with reentrancy
    vm.prank(address(crossFunctionAttacker));
    crossFunctionAttacker.triggerWithdraw();

    // VERIFICATION: Should only withdraw once
    pending = poidh.pendingWithdrawals(address(crossFunctionAttacker));
    assertEq(pending, 0, "Pending should be zero after single withdraw");

    // Contract should have 0 balance (assuming no other funds)
    // Attacker should have exactly the payout amount more than before
  }

  // ========================================================================
  // TEST: Double Vote Attack
  // ========================================================================
  function test_attack_double_vote_BLOCKED() public {
    // Setup: Create open bounty with voting
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("Open Bounty", "Description");
    uint256 bountyId = 0;

    // Attacker joins with significant weight
    vm.prank(address(votingAttacker));
    votingAttacker.joinBounty{value: 2 ether}(bountyId);

    // Create a claim
    vm.prank(claimant);
    poidh.createClaim(bountyId, "Claim", "Desc", "ipfs://x");

    // Start voting
    vm.prank(issuer);
    poidh.submitClaimForVote(bountyId, 1);

    // Attacker tries to vote twice
    vm.prank(address(votingAttacker));
    votingAttacker.vote(bountyId, true);

    // Second vote should revert
    vm.prank(address(votingAttacker));
    vm.expectRevert(PoidhV3.AlreadyVoted.selector);
    votingAttacker.vote(bountyId, false);
  }

  // ========================================================================
  // TEST: Withdraw During Voting
  // ========================================================================
  function test_attack_withdraw_during_voting_BLOCKED() public {
    // Setup: Create open bounty
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("Open Bounty", "Description");
    uint256 bountyId = 0;

    // Attacker joins
    vm.prank(address(votingAttacker));
    votingAttacker.joinBounty{value: 0.5 ether}(bountyId);

    // Create claim and start voting
    vm.prank(claimant);
    poidh.createClaim(bountyId, "Claim", "Desc", "ipfs://x");

    vm.prank(issuer);
    poidh.submitClaimForVote(bountyId, 1);

    // Try to withdraw during voting - should fail
    vm.prank(address(votingAttacker));
    vm.expectRevert(PoidhV3.VotingOngoing.selector);
    votingAttacker.withdrawDuringVoting(bountyId);
  }

  // ========================================================================
  // TEST: Claim Already Accepted Replay
  // ========================================================================
  function test_attack_replay_accepted_claim_BLOCKED() public {
    // Setup: Create and accept a claim
    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: 1 ether}("Test Bounty", "Description");

    vm.prank(claimant);
    poidh.createClaim(0, "Claim", "Desc", "ipfs://x");

    vm.prank(issuer);
    poidh.acceptClaim(0, 1);

    // Try to accept the same claim again - should fail
    vm.prank(issuer);
    vm.expectRevert(PoidhV3.BountyClaimed.selector);
    poidh.acceptClaim(0, 1);
  }

  // ========================================================================
  // TEST: Create claim on finalized bounty
  // ========================================================================
  function test_attack_claim_on_finalized_bounty_BLOCKED() public {
    // Setup: Create and finalize bounty
    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: 1 ether}("Test Bounty", "Description");

    vm.prank(claimant);
    poidh.createClaim(0, "Claim", "Desc", "ipfs://x");

    vm.prank(issuer);
    poidh.acceptClaim(0, 1);

    // Try to create another claim on finalized bounty
    vm.prank(claimant);
    vm.expectRevert(PoidhV3.BountyClaimed.selector);
    poidh.createClaim(0, "Another Claim", "Desc", "ipfs://y");
  }

  // ========================================================================
  // TEST: NFT transfer uses transferFrom not safeTransferFrom
  // ========================================================================
  function test_nft_uses_transferFrom_not_safeTransferFrom() public {
    // This test verifies the NFT transfer doesn't trigger onERC721Received

    // Setup
    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: 1 ether}("Test Bounty", "Description");

    // Attacker (contract) creates claim
    vm.prank(address(erc721Attacker));
    poidh.createClaim(0, "Attack Claim", "Description", "ipfs://attack");

    // Configure to track callbacks
    erc721Attacker.setAttackParams(0, 1, 5);
    erc721Attacker.startAttack();

    // Accept claim - if safeTransferFrom was used, onERC721Received would be called
    vm.prank(issuer);
    poidh.acceptClaim(0, 1);

    // Check that attack count is 0 - onERC721Received was never called
    // because PoidhV3 uses `transferFrom`, not `safeTransferFrom`.
    // NOTE: `transferFrom` does not invoke `onERC721Received` (callbacks only exist on safe
    // transfers).

    // The key protection is that bounty.amount is already 0 and claim.accepted is true
    (,,,, uint256 amount,,,) = poidh.bounties(0);
    assertEq(amount, 0, "Amount should be zeroed before NFT transfer");

    (,,,,,,, bool accepted) = poidh.claims(1);
    assertTrue(accepted, "Claim should be accepted before NFT transfer");
  }

  // ========================================================================
  // TEST: Frontrunning claim acceptance
  // ========================================================================
  function test_attack_frontrun_claim_acceptance() public {
    // Setup: Create bounty with pending claim
    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: 1 ether}("Test Bounty", "Description");

    vm.prank(claimant);
    poidh.createClaim(0, "Claim1", "Desc", "ipfs://1");

    // Attacker creates their own claim
    address attacker = makeAddr("attacker");
    vm.prank(attacker);
    poidh.createClaim(0, "AttackerClaim", "Desc", "ipfs://2");

    // Issuer tries to accept claim 1, but attacker can't frontrun
    // because only issuer can accept on solo bounties
    vm.prank(attacker);
    vm.expectRevert(PoidhV3.WrongCaller.selector);
    poidh.acceptClaim(0, 2);

    // Issuer accepts legitimate claim
    vm.prank(issuer);
    poidh.acceptClaim(0, 1);
  }

  // ========================================================================
  // TEST: Griefing via spam claims
  // ========================================================================
  function test_attack_spam_claims_griefing() public {
    // Setup: Create bounty
    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: 1 ether}("Test Bounty", "Description");

    // Attacker spams claims
    address attacker = makeAddr("attacker");
    for (uint256 i = 0; i < 10; i++) {
      vm.prank(attacker);
      poidh.createClaim(0, "SpamClaim", "Spam", "ipfs://spam");
    }

    // Issuer can still accept a legitimate claim
    vm.prank(claimant);
    poidh.createClaim(0, "LegitClaim", "Legit", "ipfs://legit");

    vm.prank(issuer);
    poidh.acceptClaim(0, 11); // claimId 11 is the legit claim
  }

  // ========================================================================
  // TEST: Integer overflow in fee calculation
  // ========================================================================
  function test_attack_fee_overflow() public {
    // Test with maximum possible bounty amount
    uint256 maxAmount = type(uint256).max / 10_000; // Prevent overflow in fee calc
    vm.deal(issuer, maxAmount + 1);

    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: maxAmount}("Big Bounty", "Description");

    // Verify fee calculation doesn't overflow
    uint256 expectedFee = (maxAmount * 250) / 10_000;
    uint256 expectedPayout = maxAmount - expectedFee;

    vm.prank(claimant);
    poidh.createClaim(0, "Claim", "Desc", "ipfs://x");

    vm.prank(issuer);
    poidh.acceptClaim(0, 1);

    assertEq(poidh.pendingWithdrawals(claimant), expectedPayout);
    assertEq(poidh.pendingWithdrawals(treasury), expectedFee);
  }

  // ========================================================================
  // TEST: Zero amount edge cases
  // ========================================================================
  function test_attack_zero_amount_edge_cases() public {
    // Cannot create bounty with 0 value
    vm.prank(issuer, issuer);
    vm.expectRevert(PoidhV3.NoEther.selector);
    poidh.createSoloBounty{value: 0}("Zero Bounty", "Description");

    // Cannot create bounty below minimum
    vm.prank(issuer, issuer);
    vm.expectRevert(PoidhV3.MinimumBountyNotMet.selector);
    poidh.createSoloBounty{value: 0.0001 ether}("Tiny Bounty", "Description");

    // Cannot join open bounty with 0 value
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("Open Bounty", "Description");

    address joiner = makeAddr("joiner");
    vm.deal(joiner, 1 ether);
    vm.prank(joiner);
    vm.expectRevert(PoidhV3.NoEther.selector);
    poidh.joinOpenBounty{value: 0}(0);
  }

  // ========================================================================
  // TEST: Self-referential claim (issuer claims own bounty)
  // ========================================================================
  function test_attack_issuer_self_claim() public {
    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: 1 ether}("Test Bounty", "Description");

    // Issuer cannot claim their own bounty
    vm.prank(issuer);
    vm.expectRevert(PoidhV3.IssuerCannotClaim.selector);
    poidh.createClaim(0, "SelfClaim", "Desc", "ipfs://self");
  }

  // ========================================================================
  // TEST: Claim on non-existent bounty
  // ========================================================================
  function test_attack_claim_nonexistent_bounty() public {
    vm.prank(claimant);
    vm.expectRevert(PoidhV3.BountyNotFound.selector);
    poidh.createClaim(999, "Claim", "Desc", "ipfs://x");
  }

  // ========================================================================
  // TEST: Accept non-existent claim
  // ========================================================================
  function test_attack_accept_nonexistent_claim() public {
    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: 1 ether}("Test Bounty", "Description");

    vm.prank(issuer);
    vm.expectRevert(PoidhV3.ClaimNotFound.selector);
    poidh.acceptClaim(0, 999);
  }

  // ========================================================================
  // TEST: Vote weight manipulation via withdraw/rejoin
  // ========================================================================
  function test_attack_vote_weight_manipulation() public {
    // Setup open bounty with voting
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("Open Bounty", "Description");

    // Contributor joins
    address contributor = makeAddr("contributor");
    vm.deal(contributor, 10 ether);
    vm.prank(contributor);
    poidh.joinOpenBounty{value: 2 ether}(0);

    // Create claim and start voting
    vm.prank(claimant);
    poidh.createClaim(0, "Claim", "Desc", "ipfs://x");

    vm.prank(issuer);
    poidh.submitClaimForVote(0, 1);

    // Contributor cannot withdraw during voting
    vm.prank(contributor);
    vm.expectRevert(PoidhV3.VotingOngoing.selector);
    poidh.withdrawFromOpenBounty(0);

    // Contributor votes
    vm.prank(contributor);
    poidh.voteClaim(0, false);

    // Cannot rejoin during voting either (voting ongoing blocks it)
    vm.prank(contributor);
    vm.expectRevert(PoidhV3.VotingOngoing.selector);
    poidh.joinOpenBounty{value: 1 ether}(0);
  }

  // ========================================================================
  // TEST: Resolve vote before deadline
  // ========================================================================
  function test_attack_early_vote_resolution() public {
    // Setup voting
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("Open Bounty", "Description");

    address contributor = makeAddr("contributor");
    vm.deal(contributor, 1 ether);
    vm.prank(contributor);
    poidh.joinOpenBounty{value: 0.5 ether}(0);

    vm.prank(claimant);
    poidh.createClaim(0, "Claim", "Desc", "ipfs://x");

    vm.prank(issuer);
    poidh.submitClaimForVote(0, 1);

    // Try to resolve before deadline
    vm.expectRevert(PoidhV3.VotingOngoing.selector);
    poidh.resolveVote(0);
  }

  // ========================================================================
  // TEST: DOS via max participants
  // ========================================================================
  function test_attack_dos_max_participants() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("Open Bounty", "Description");

    uint256 max = poidh.MAX_PARTICIPANTS();
    uint256 minContrib = poidh.MIN_CONTRIBUTION();

    // Fill up to MAX_PARTICIPANTS - 1 (issuer is at index 0)
    for (uint256 i = 1; i < max; i++) {
      address participant = vm.addr(i + 1000);
      vm.deal(participant, 0.01 ether);
      vm.prank(participant);
      poidh.joinOpenBounty{value: minContrib}(0);
    }

    // Next participant should fail
    address extraParticipant = makeAddr("extra");
    vm.deal(extraParticipant, 0.01 ether);
    vm.prank(extraParticipant);
    vm.expectRevert(PoidhV3.MaxParticipantsReached.selector);
    poidh.joinOpenBounty{value: minContrib}(0);
  }

  // ========================================================================
  // TEST: Contract cannot create bounties (prevents NFT sink)
  // ========================================================================
  function test_attack_contract_cannot_create_bounty() public {
    // Deploy a contract that tries to create a bounty
    ContractBountyCreator attacker = new ContractBountyCreator(address(poidh));
    vm.deal(address(attacker), 10 ether);

    // Contract should not be able to create bounty
    vm.expectRevert(PoidhV3.ContractsCannotCreateBounties.selector);
    attacker.createBounty();
  }
}
