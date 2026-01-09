// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoidhDeployHelper} from "./utils/PoidhDeployHelper.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PoidhV3} from "../src/PoidhV3.sol";
import {PoidhClaimNFT} from "../src/PoidhClaimNFT.sol";

contract RejectingReceiver {
  PoidhV3 public immutable poidh;

  constructor(PoidhV3 poidh_) {
    poidh = poidh_;
  }

  function createClaim(uint256 bountyId) external {
    poidh.createClaim(bountyId, "claim", "desc", "ipfs://x");
  }

  function withdraw() external {
    poidh.withdraw();
  }

  receive() external payable {
    revert("nope");
  }
}

contract ContractBountyCreator {
  PoidhV3 public immutable poidh;

  constructor(address poidh_) {
    poidh = PoidhV3(payable(poidh_));
  }

  function createSoloBounty() external {
    poidh.createSoloBounty{value: 1 ether}("Contract Solo", "desc");
  }

  function createOpenBounty() external {
    poidh.createOpenBounty{value: 1 ether}("Contract Open", "desc");
  }

  receive() external payable {}
}

contract ReenteringWithdrawReceiver {
  PoidhV3 public immutable poidh;

  bool public sawReentrancyError;

  constructor(PoidhV3 poidh_) {
    poidh = poidh_;
  }

  function createClaim(uint256 bountyId) external {
    poidh.createClaim(bountyId, "claim", "desc", "ipfs://x");
  }

  function withdraw() external {
    poidh.withdraw();
  }

  receive() external payable {
    try poidh.withdraw() {}
    catch (bytes memory reason) {
      if (
        reason.length >= 4
          // forge-lint: disable-next-line(unsafe-typecast)
          && bytes4(reason) == ReentrancyGuard.ReentrancyGuardReentrantCall.selector
      ) sawReentrancyError = true;
    }
  }
}

contract PoidhV3UnitTest is PoidhDeployHelper {
  PoidhV3 poidh;
  PoidhClaimNFT nft;

  address treasury;
  address issuer;
  address claimant;
  address claimant2;
  address contributor;
  address contributor2;

  bytes32 private constant BOUNTY_CREATED_SIG =
    keccak256("BountyCreated(uint256,address,string,string,uint256,uint256,bool)");
  bytes32 private constant CLAIM_CREATED_SIG =
    keccak256("ClaimCreated(uint256,address,uint256,address,string,string,uint256,string)");
  bytes32 private constant BOUNTY_JOINED_SIG =
    keccak256("BountyJoined(uint256,address,uint256,uint256)");
  bytes32 private constant WITHDRAW_FROM_OPEN_BOUNTY_SIG =
    keccak256("WithdrawFromOpenBounty(uint256,address,uint256,uint256)");
  bytes32 private constant VOTING_STARTED_SIG =
    keccak256("VotingStarted(uint256,uint256,uint256,uint256,uint256)");
  bytes32 private constant VOTE_CAST_SIG =
    keccak256("VoteCast(address,uint256,uint256,bool,uint256)");
  bytes32 private constant VOTING_RESOLVED_SIG =
    keccak256("VotingResolved(uint256,uint256,bool,uint256,uint256)");

  bytes32 private constant CLAIM_SUBMITTED_FOR_VOTE_SIG =
    keccak256("ClaimSubmittedForVote(uint256,uint256)");
  bytes32 private constant RESET_VOTING_PERIOD_SIG = keccak256("ResetVotingPeriod(uint256)");
  bytes32 private constant VOTE_CLAIM_SIG = keccak256("VoteClaim(address,uint256,uint256)");

  function setUp() public {
    vm.txGasPrice(0);

    treasury = makeAddr("treasury");
    issuer = makeAddr("issuer");
    claimant = makeAddr("claimant");
    claimant2 = makeAddr("claimant2");
    contributor = makeAddr("contributor");
    contributor2 = makeAddr("contributor2");

    (poidh, nft) = deployPoidh(treasury, 1);

    vm.deal(issuer, 1000 ether);
    vm.deal(claimant, 1000 ether);
    vm.deal(claimant2, 1000 ether);
    vm.deal(contributor, 1000 ether);
    vm.deal(contributor2, 1000 ether);
  }

  function test_constructor_reverts_treasury_zero() public {
    PoidhClaimNFT localNft = new PoidhClaimNFT("poidh claims v3", "POIDH3", address(0xBEEF));
    vm.expectRevert(abi.encodeWithSelector(PoidhV3.InvalidTreasury.selector, address(0)));
    new PoidhV3(
      address(localNft),
      address(0),
      1,
      DEFAULT_MIN_BOUNTY_AMOUNT,
      DEFAULT_MIN_CONTRIBUTION
    );
  }

  function test_constructor_reverts_startClaimIndex_zero() public {
    PoidhClaimNFT localNft = new PoidhClaimNFT("poidh claims v3", "POIDH3", address(0xBEEF));
    vm.expectRevert(PoidhV3.InvalidStartClaimIndex.selector);
    new PoidhV3(
      address(localNft),
      treasury,
      0,
      DEFAULT_MIN_BOUNTY_AMOUNT,
      DEFAULT_MIN_CONTRIBUTION
    );
  }

  function test_constructor_reverts_minBounty_zero() public {
    PoidhClaimNFT localNft = new PoidhClaimNFT("poidh claims v3", "POIDH3", address(0xBEEF));
    vm.expectRevert(abi.encodeWithSelector(PoidhV3.InvalidMinBountyAmount.selector, 0));
    new PoidhV3(address(localNft), treasury, 1, 0, DEFAULT_MIN_CONTRIBUTION);
  }

  function test_constructor_reverts_minContribution_zero() public {
    PoidhClaimNFT localNft = new PoidhClaimNFT("poidh claims v3", "POIDH3", address(0xBEEF));
    vm.expectRevert(abi.encodeWithSelector(PoidhV3.InvalidMinContribution.selector, 0));
    new PoidhV3(address(localNft), treasury, 1, DEFAULT_MIN_BOUNTY_AMOUNT, 0);
  }

  function test_contracts_cannot_create_bounties() public {
    // Deploy a contract that will try to create a bounty
    ContractBountyCreator contractCreator = new ContractBountyCreator(address(poidh));
    vm.deal(address(contractCreator), 10 ether);

    // Contract should not be able to create bounty
    vm.expectRevert(PoidhV3.ContractsCannotCreateBounties.selector);
    contractCreator.createSoloBounty();

    vm.expectRevert(PoidhV3.ContractsCannotCreateBounties.selector);
    contractCreator.createOpenBounty();
  }

  function test_minimum_contribution_for_join() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    // Try to join with less than minimum
    address joiner = makeAddr("joiner");
    vm.deal(joiner, 1 ether);
    uint256 min = poidh.MIN_CONTRIBUTION();
    vm.prank(joiner);
    vm.expectRevert(PoidhV3.MinimumContributionNotMet.selector);
    poidh.joinOpenBounty{value: min - 1}(0);

    // Join with minimum works
    vm.prank(joiner);
    poidh.joinOpenBounty{value: min}(0);
  }

  function test_createSoloBounty_reverts_noEther() public {
    vm.prank(issuer, issuer);
    vm.expectRevert(PoidhV3.NoEther.selector);
    poidh.createSoloBounty("solo", "desc");
  }

  function test_createSoloBounty_reverts_below_min() public {
    uint256 min = poidh.MIN_BOUNTY_AMOUNT();
    vm.prank(issuer, issuer);
    vm.expectRevert(PoidhV3.MinimumBountyNotMet.selector);
    poidh.createSoloBounty{value: min - 1}("solo", "desc");
  }

  function test_createOpenBounty_sets_issuer_participant() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    (address[] memory p, uint256[] memory a) = poidh.getParticipants(0);
    assertEq(p.length, 1);
    assertEq(a.length, 1);
    assertEq(p[0], issuer);
    assertEq(a[0], 1 ether);
    assertEq(poidh.everHadExternalContributor(0), false);
  }

  function test_joinOpenBounty_reverts_issuer() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(issuer);
    vm.expectRevert(PoidhV3.WrongCaller.selector);
    poidh.joinOpenBounty{value: 1 ether}(0); // Use 1 ether to pass MIN_CONTRIBUTION check first
  }

  function test_joinOpenBounty_reverts_noEther() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(contributor);
    vm.expectRevert(PoidhV3.NoEther.selector);
    poidh.joinOpenBounty(0);
  }

  function test_joinOpenBounty_accumulates_existing_contributor() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(contributor);
    poidh.joinOpenBounty{value: 2 ether}(0);
    vm.prank(contributor);
    poidh.joinOpenBounty{value: 3 ether}(0);

    (address[] memory p, uint256[] memory a) = poidh.getParticipants(0);
    assertEq(p.length, 2);
    assertEq(p[1], contributor);
    assertEq(a[1], 5 ether);
    assertEq(poidh.everHadExternalContributor(0), true);
  }

  function test_withdrawFromOpenBounty_clears_slot_and_allows_rejoin() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(contributor);
    poidh.joinOpenBounty{value: 2 ether}(0);

    vm.prank(contributor);
    poidh.withdrawFromOpenBounty(0);

    assertEq(poidh.pendingWithdrawals(contributor), 2 ether);

    (address[] memory p1, uint256[] memory a1) = poidh.getParticipants(0);
    assertEq(p1.length, 2);
    assertEq(p1[1], address(0));
    assertEq(a1[1], 0);

    vm.prank(contributor);
    poidh.joinOpenBounty{value: 7 ether}(0);

    (address[] memory p2, uint256[] memory a2) = poidh.getParticipants(0);
    assertEq(p2.length, 2);
    assertEq(p2[1], contributor);
    assertEq(a2[1], 7 ether);
  }

  function test_withdrawFromOpenBounty_reverts_notActiveParticipant() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(contributor);
    vm.expectRevert(PoidhV3.NotActiveParticipant.selector);
    poidh.withdrawFromOpenBounty(0);
  }

  function test_withdrawFromOpenBounty_reverts_issuer() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(issuer);
    vm.expectRevert(PoidhV3.IssuerCannotWithdraw.selector);
    poidh.withdrawFromOpenBounty(0);
  }

  function test_joinOpenBounty_reverts_when_max_participants_reached() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    uint256 minContrib = poidh.MIN_CONTRIBUTION();
    uint256 max = poidh.MAX_PARTICIPANTS();
    for (uint256 i = 1; i < max; i++) {
      address p = vm.addr(10_000 + i);
      vm.deal(p, 1 ether);
      vm.prank(p);
      poidh.joinOpenBounty{value: minContrib}(0);
    }

    address extra = address(0x9999);
    vm.deal(extra, 1 ether);
    vm.prank(extra);
    vm.expectRevert(PoidhV3.MaxParticipantsReached.selector);
    poidh.joinOpenBounty{value: minContrib}(0);
  }

  function test_cancelSoloBounty_closes_and_refunds() public {
    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: 1 ether}("solo", "desc");

    vm.prank(issuer);
    poidh.cancelSoloBounty(0);

    assertEq(poidh.pendingWithdrawals(issuer), 1 ether);

    // Closed bounties can't accept claims.
    vm.prank(claimant);
    vm.expectRevert(PoidhV3.BountyClosed.selector);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");
  }

  function test_cancelOpenBounty_refunds_issuer_and_contributors_claim() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(contributor);
    poidh.joinOpenBounty{value: 2 ether}(0);

    vm.prank(issuer);
    poidh.cancelOpenBounty(0);

    assertEq(poidh.pendingWithdrawals(issuer), 1 ether);

    vm.prank(contributor);
    poidh.claimRefundFromCancelledOpenBounty(0);

    assertEq(poidh.pendingWithdrawals(contributor), 2 ether);
  }

  function test_claimRefundFromCancelledOpenBounty_reverts_if_not_cancelled() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(contributor);
    vm.expectRevert(PoidhV3.NotCancelledOpenBounty.selector);
    poidh.claimRefundFromCancelledOpenBounty(0);
  }

  function test_createClaim_mints_to_escrow_and_indexes() public {
    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: 1 ether}("solo", "desc");

    vm.prank(claimant);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");

    assertEq(nft.ownerOf(1), address(poidh));

    assertEq(poidh.userClaims(claimant, 0), 1);
    assertEq(poidh.bountyClaims(0, 0), 1);
  }

  function test_createClaim_reverts_for_issuer() public {
    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: 1 ether}("solo", "desc");

    vm.prank(issuer);
    vm.expectRevert(PoidhV3.IssuerCannotClaim.selector);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");
  }

  function test_createClaim_reverts_while_voting_ongoing() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(contributor);
    poidh.joinOpenBounty{value: 1 ether}(0);

    vm.prank(claimant);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");

    vm.prank(issuer);
    poidh.submitClaimForVote(0, 1);

    vm.prank(claimant2);
    vm.expectRevert(PoidhV3.VotingOngoing.selector);
    poidh.createClaim(0, "claim2", "desc", "ipfs://y");
  }

  function test_submitClaimForVote_reverts_for_reserved_claimId_zero() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(issuer);
    vm.expectRevert(PoidhV3.ClaimNotFound.selector);
    poidh.submitClaimForVote(0, 0);
  }

  function test_submitClaimForVote_issuer_cannot_vote_again() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(contributor);
    poidh.joinOpenBounty{value: 1 ether}(0);

    vm.prank(claimant);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");

    vm.prank(issuer);
    poidh.submitClaimForVote(0, 1);

    vm.prank(issuer);
    vm.expectRevert(PoidhV3.AlreadyVoted.selector);
    poidh.voteClaim(0, true);
  }

  function test_voteClaim_reverts_double_vote() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(contributor);
    poidh.joinOpenBounty{value: 1 ether}(0);

    vm.prank(claimant);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");

    vm.prank(issuer);
    poidh.submitClaimForVote(0, 1);

    vm.prank(contributor);
    poidh.voteClaim(0, true);

    vm.prank(contributor);
    vm.expectRevert(PoidhV3.AlreadyVoted.selector);
    poidh.voteClaim(0, true);
  }

  function test_voteClaim_reverts_after_deadline() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(contributor);
    poidh.joinOpenBounty{value: 1 ether}(0);

    vm.prank(claimant);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");

    vm.prank(issuer);
    poidh.submitClaimForVote(0, 1);

    vm.warp(block.timestamp + poidh.votingPeriod());

    vm.prank(contributor);
    vm.expectRevert(PoidhV3.VotingEnded.selector);
    poidh.voteClaim(0, true);
  }

  function test_resolveVote_reverts_before_deadline() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(contributor);
    poidh.joinOpenBounty{value: 1 ether}(0);

    vm.prank(claimant);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");

    vm.prank(issuer);
    poidh.submitClaimForVote(0, 1);

    vm.expectRevert(PoidhV3.VotingOngoing.selector);
    poidh.resolveVote(0);
  }

  function test_resetVotingPeriod_reverts_when_vote_would_pass() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 2 ether}("open", "desc");

    vm.prank(contributor);
    poidh.joinOpenBounty{value: 1 ether}(0);

    vm.prank(claimant);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");

    vm.prank(issuer);
    poidh.submitClaimForVote(0, 1);

    vm.prank(contributor);
    poidh.voteClaim(0, false);

    vm.warp(block.timestamp + poidh.votingPeriod());

    vm.expectRevert(PoidhV3.VoteWouldPass.selector);
    poidh.resetVotingPeriod(0);
  }

  function test_resetVotingPeriod_resets_losing_vote() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(contributor);
    poidh.joinOpenBounty{value: 2 ether}(0);

    vm.prank(claimant);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");

    vm.prank(issuer);
    poidh.submitClaimForVote(0, 1);

    vm.prank(contributor);
    poidh.voteClaim(0, false);

    vm.warp(block.timestamp + poidh.votingPeriod());

    poidh.resetVotingPeriod(0);
    assertEq(poidh.bountyCurrentVotingClaim(0), 0);
    (uint256 yes, uint256 no, uint256 deadline) = poidh.bountyVotingTracker(0);
    assertEq(yes, 0);
    assertEq(no, 0);
    assertEq(deadline, 0);

    // New vote round can start.
    vm.prank(issuer);
    poidh.submitClaimForVote(0, 1);
    assertEq(poidh.bountyCurrentVotingClaim(0), 1);
  }

  function test_acceptClaim_openBounty_direct_only_if_no_external_ever() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(claimant);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");

    vm.prank(issuer);
    poidh.acceptClaim(0, 1);

    assertEq(nft.ownerOf(1), issuer);
  }

  function test_acceptClaim_openBounty_reverts_if_external_contributed() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(contributor);
    poidh.joinOpenBounty{value: 1 ether}(0);

    vm.prank(claimant);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");

    vm.prank(issuer);
    vm.expectRevert(PoidhV3.NotSoloBounty.selector);
    poidh.acceptClaim(0, 1);
  }

  function test_acceptClaim_openBounty_after_external_withdraw_still_requires_vote() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(contributor);
    poidh.joinOpenBounty{value: 1 ether}(0);

    vm.prank(contributor);
    poidh.withdrawFromOpenBounty(0);

    vm.prank(claimant);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");

    vm.prank(issuer);
    vm.expectRevert(PoidhV3.NotSoloBounty.selector);
    poidh.acceptClaim(0, 1);

    vm.prank(issuer);
    poidh.submitClaimForVote(0, 1);

    vm.warp(block.timestamp + poidh.votingPeriod());
    poidh.resolveVote(0);

    assertEq(nft.ownerOf(1), issuer);
    assertEq(poidh.pendingWithdrawals(claimant), 0.975 ether);
    assertEq(poidh.pendingWithdrawals(treasury), 0.025 ether);
    assertEq(poidh.pendingWithdrawals(contributor), 1 ether);
  }

  function test_withdraw_sends_eth_and_zeros_pending() public {
    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: 1 ether}("solo", "desc");

    vm.prank(claimant);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");

    vm.prank(issuer);
    poidh.acceptClaim(0, 1);

    uint256 payout = poidh.pendingWithdrawals(claimant);
    uint256 claimantBalBefore = claimant.balance;

    vm.prank(claimant);
    poidh.withdraw();

    assertEq(poidh.pendingWithdrawals(claimant), 0);
    assertEq(claimant.balance, claimantBalBefore + payout);
  }

  function test_withdraw_reverts_transferFailed_if_receiver_reverts() public {
    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: 1 ether}("solo", "desc");

    RejectingReceiver r = new RejectingReceiver(poidh);
    vm.deal(address(r), 1 ether);

    r.createClaim(0);

    vm.prank(issuer);
    poidh.acceptClaim(0, 1);

    assertGt(poidh.pendingWithdrawals(address(r)), 0);

    vm.expectRevert(PoidhV3.TransferFailed.selector);
    r.withdraw();

    assertGt(poidh.pendingWithdrawals(address(r)), 0);
  }

  function test_withdraw_blocks_reentrancy_but_still_succeeds() public {
    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: 1 ether}("solo", "desc");

    ReenteringWithdrawReceiver r = new ReenteringWithdrawReceiver(poidh);
    vm.deal(address(r), 1 ether);

    r.createClaim(0);

    vm.prank(issuer);
    poidh.acceptClaim(0, 1);

    uint256 pending = poidh.pendingWithdrawals(address(r));
    assertGt(pending, 0);

    r.withdraw();

    assertEq(poidh.pendingWithdrawals(address(r)), 0);
    assertEq(address(r).balance, 1 ether + pending);
    assertTrue(r.sawReentrancyError());
  }

  function test_event_bountyCreated_includes_isOpenBounty() public {
    vm.recordLogs();
    vm.prank(issuer, issuer);
    uint256 soloTimestamp = block.timestamp;
    poidh.createSoloBounty{value: 1 ether}("solo", "desc");

    Vm.Log[] memory logs = vm.getRecordedLogs();
    Vm.Log memory log = _findLog(logs, BOUNTY_CREATED_SIG);

    assertEq(uint256(log.topics[1]), 0);
    assertEq(address(uint160(uint256(log.topics[2]))), issuer);

    (string memory title, string memory description, uint256 amount, uint256 createdAt, bool isOpen)
    = abi.decode(log.data, (string, string, uint256, uint256, bool));

    assertEq(title, "solo");
    assertEq(description, "desc");
    assertEq(amount, 1 ether);
    assertEq(createdAt, soloTimestamp);
    assertTrue(!isOpen);

    vm.recordLogs();
    vm.prank(issuer, issuer);
    uint256 openTimestamp = block.timestamp;
    poidh.createOpenBounty{value: 2 ether}("open", "desc2");

    logs = vm.getRecordedLogs();
    log = _findLog(logs, BOUNTY_CREATED_SIG);

    assertEq(uint256(log.topics[1]), 1);
    assertEq(address(uint160(uint256(log.topics[2]))), issuer);

    (title, description, amount, createdAt, isOpen) =
      abi.decode(log.data, (string, string, uint256, uint256, bool));

    assertEq(title, "open");
    assertEq(description, "desc2");
    assertEq(amount, 2 ether);
    assertEq(createdAt, openTimestamp);
    assertTrue(isOpen);
  }

  function test_event_claimCreated_includes_imageUri() public {
    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: 1 ether}("solo", "desc");

    vm.recordLogs();
    vm.prank(claimant);
    uint256 createdAt = block.timestamp;
    poidh.createClaim(0, "claim", "desc", "ipfs://image");

    Vm.Log[] memory logs = vm.getRecordedLogs();
    Vm.Log memory log = _findLog(logs, CLAIM_CREATED_SIG);

    assertEq(uint256(log.topics[1]), 1);
    assertEq(address(uint160(uint256(log.topics[2]))), claimant);
    assertEq(uint256(log.topics[3]), 0);

    (
      address bountyIssuer,
      string memory title,
      string memory description,
      uint256 eventTimestamp,
      string memory imageUri
    ) = abi.decode(log.data, (address, string, string, uint256, string));

    assertEq(bountyIssuer, issuer);
    assertEq(title, "claim");
    assertEq(description, "desc");
    assertEq(eventTimestamp, createdAt);
    assertEq(imageUri, "ipfs://image");
  }

  function test_event_bountyJoined_includes_latestBalance() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.recordLogs();
    vm.prank(contributor);
    poidh.joinOpenBounty{value: 2 ether}(0);

    Vm.Log[] memory logs = vm.getRecordedLogs();
    Vm.Log memory log = _findLog(logs, BOUNTY_JOINED_SIG);

    assertEq(uint256(log.topics[1]), 0);
    assertEq(address(uint160(uint256(log.topics[2]))), contributor);

    (uint256 amount, uint256 latestBountyBalance) =
      abi.decode(log.data, (uint256, uint256));

    assertEq(amount, 2 ether);
    assertEq(latestBountyBalance, 3 ether);
  }

  function test_event_withdrawFromOpenBounty_includes_latestAmount() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(contributor);
    poidh.joinOpenBounty{value: 2 ether}(0);

    vm.recordLogs();
    vm.prank(contributor);
    poidh.withdrawFromOpenBounty(0);

    Vm.Log[] memory logs = vm.getRecordedLogs();
    Vm.Log memory log = _findLog(logs, WITHDRAW_FROM_OPEN_BOUNTY_SIG);

    assertEq(uint256(log.topics[1]), 0);
    assertEq(address(uint160(uint256(log.topics[2]))), contributor);

    (uint256 amount, uint256 latestBountyAmount) =
      abi.decode(log.data, (uint256, uint256));

    assertEq(amount, 2 ether);
    assertEq(latestBountyAmount, 1 ether);
  }

  function test_event_votingStarted_includes_round_and_no_legacy_events() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(contributor);
    poidh.joinOpenBounty{value: 1 ether}(0);

    vm.prank(claimant);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");

    vm.recordLogs();
    vm.prank(issuer);
    uint256 expectedDeadline = block.timestamp + poidh.votingPeriod();
    poidh.submitClaimForVote(0, 1);

    Vm.Log[] memory logs = vm.getRecordedLogs();
    Vm.Log memory log = _findLog(logs, VOTING_STARTED_SIG);

    assertEq(uint256(log.topics[1]), 0);
    assertEq(uint256(log.topics[2]), 1);

    (uint256 deadline, uint256 issuerYesWeight, uint256 round) =
      abi.decode(log.data, (uint256, uint256, uint256));

    assertEq(deadline, expectedDeadline);
    assertEq(issuerYesWeight, 1 ether);
    assertEq(round, 1);

    _assertNoLog(logs, CLAIM_SUBMITTED_FOR_VOTE_SIG);
    _assertNoLog(logs, VOTE_CAST_SIG);
  }

  function test_event_voteClaim_emits_voteCast_and_no_voteClaim() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(contributor);
    poidh.joinOpenBounty{value: 1 ether}(0);

    vm.prank(claimant);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");

    vm.prank(issuer);
    poidh.submitClaimForVote(0, 1);

    vm.recordLogs();
    vm.prank(contributor);
    poidh.voteClaim(0, true);

    Vm.Log[] memory logs = vm.getRecordedLogs();
    Vm.Log memory log = _findLog(logs, VOTE_CAST_SIG);

    assertEq(address(uint160(uint256(log.topics[1]))), contributor);
    assertEq(uint256(log.topics[2]), 0);
    assertEq(uint256(log.topics[3]), 1);

    (bool support, uint256 weight) = abi.decode(log.data, (bool, uint256));
    assertTrue(support);
    assertEq(weight, 1 ether);

    _assertNoLog(logs, VOTE_CLAIM_SIG);
  }

  function test_event_resetVotingPeriod_emits_no_reset_event() public {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");

    vm.prank(contributor);
    poidh.joinOpenBounty{value: 1 ether}(0);

    vm.prank(claimant);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");

    vm.prank(issuer);
    poidh.submitClaimForVote(0, 1);

    vm.prank(contributor);
    poidh.voteClaim(0, false);

    vm.warp(block.timestamp + poidh.votingPeriod());

    vm.recordLogs();
    poidh.resetVotingPeriod(0);

    Vm.Log[] memory logs = vm.getRecordedLogs();
    _assertNoLog(logs, RESET_VOTING_PERIOD_SIG);

    Vm.Log memory log = _findLog(logs, VOTING_RESOLVED_SIG);
    (bool passed, uint256 yes, uint256 no) = abi.decode(log.data, (bool, uint256, uint256));
    assertTrue(!passed);
    assertEq(yes + no, 2 ether);
  }

  function _findLog(Vm.Log[] memory logs, bytes32 sig) internal pure returns (Vm.Log memory) {
    for (uint256 i = 0; i < logs.length; i++) {
      if (logs[i].topics.length > 0 && logs[i].topics[0] == sig) {
        return logs[i];
      }
    }
    revert("log not found");
  }

  function _assertNoLog(Vm.Log[] memory logs, bytes32 sig) internal pure {
    for (uint256 i = 0; i < logs.length; i++) {
      if (logs[i].topics.length > 0 && logs[i].topics[0] == sig) {
        revert("unexpected log");
      }
    }
  }
}
