// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PoidhV3} from "../src/PoidhV3.sol";
import {PoidhClaimNFT} from "../src/PoidhClaimNFT.sol";

/// @notice Extra/edge-case tests that exercise defensive branches and deployment footguns.
/// @dev This suite intentionally avoids storage-slot corruption tests to keep the tests robust
/// against future storage layout changes.
contract PoidhV3CoverageTest is Test {
  PoidhV3 poidh;
  PoidhClaimNFT nft;

  address treasury;
  address issuer;
  address claimant;
  address contributor;
  address other;

  function setUp() public {
    vm.txGasPrice(0);

    treasury = makeAddr("treasury");
    issuer = makeAddr("issuer");
    claimant = makeAddr("claimant");
    contributor = makeAddr("contributor");
    other = makeAddr("other");

    nft = new PoidhClaimNFT("poidh claims v3", "POIDH3");
    poidh = new PoidhV3(address(nft), treasury, 1);
    nft.setPoidh(address(poidh));

    vm.deal(issuer, 10_000 ether);
    vm.deal(claimant, 10_000 ether);
    vm.deal(contributor, 10_000 ether);
    vm.deal(other, 10_000 ether);
  }

  function _createSolo(uint256 amount) internal returns (uint256 bountyId) {
    bountyId = poidh.bountyCounter();
    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: amount}("solo", "desc");
  }

  function _createOpen(uint256 amount) internal returns (uint256 bountyId) {
    bountyId = poidh.bountyCounter();
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: amount}("open", "desc");
  }

  function _createClaim(uint256 bountyId, address who) internal returns (uint256 claimId) {
    claimId = poidh.claimCounter();
    vm.prank(who);
    poidh.createClaim(bountyId, "claim", "desc", "ipfs://x");
  }

  function test_withdraw_reverts_nothingToWithdraw() public {
    vm.expectRevert(PoidhV3.NothingToWithdraw.selector);
    poidh.withdraw();
  }

  function test_withdrawTo_sends_to_different_address() public {
    _createSolo(1 ether);

    vm.prank(issuer);
    poidh.cancelSoloBounty(0);

    address receiver = makeAddr("receiver");
    uint256 balBefore = receiver.balance;

    vm.prank(issuer);
    poidh.withdrawTo(payable(receiver));

    assertEq(poidh.pendingWithdrawals(issuer), 0);
    assertEq(receiver.balance, balBefore + 1 ether);
  }

  function test_receive_reverts_directEtherNotAccepted() public {
    vm.expectRevert(PoidhV3.DirectEtherNotAccepted.selector);
    (bool ok,) = address(poidh).call{value: 1 wei}("");
    ok;
  }

  function test_vote_weight_snapshot_blocks_join_and_uses_snapshot() public {
    _createOpen(1 ether);

    vm.prank(contributor);
    poidh.joinOpenBounty{value: 0.5 ether}(0);

    _createClaim(0, claimant);

    vm.prank(issuer);
    poidh.submitClaimForVote(0, 1);

    address lateJoiner = makeAddr("lateJoiner");
    vm.deal(lateJoiner, 10 ether);
    vm.prank(lateJoiner);
    vm.expectRevert(PoidhV3.VotingOngoing.selector);
    poidh.joinOpenBounty{value: 1 ether}(0);

    vm.prank(contributor);
    poidh.voteClaim(0, true);

    assertEq(poidh.voteWeightSnapshot(0, contributor), 0.5 ether);
  }

  function test_bountyNotFound_reverts_in_multiple_entrypoints() public {
    uint256 minContrib = poidh.MIN_CONTRIBUTION();

    vm.prank(claimant);
    vm.expectRevert(PoidhV3.BountyNotFound.selector);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");

    vm.prank(contributor);
    vm.expectRevert(PoidhV3.BountyNotFound.selector);
    poidh.joinOpenBounty{value: minContrib}(0);

    vm.expectRevert(PoidhV3.BountyNotFound.selector);
    poidh.cancelSoloBounty(0);

    vm.expectRevert(PoidhV3.BountyNotFound.selector);
    poidh.cancelOpenBounty(0);

    vm.expectRevert(PoidhV3.BountyNotFound.selector);
    poidh.claimRefundFromCancelledOpenBounty(0);

    vm.expectRevert(PoidhV3.BountyNotFound.selector);
    poidh.voteClaim(0, true);

    vm.expectRevert(PoidhV3.BountyNotFound.selector);
    poidh.resetVotingPeriod(0);
  }

  function test_joinOpenBounty_reverts_notOpenBounty_on_solo() public {
    _createSolo(1 ether);

    uint256 minContrib = poidh.MIN_CONTRIBUTION();
    vm.prank(contributor);
    vm.expectRevert(PoidhV3.NotOpenBounty.selector);
    poidh.joinOpenBounty{value: minContrib}(0);
  }

  function test_cancelSoloBounty_reverts_notSoloBounty_and_wrongCaller() public {
    _createOpen(1 ether);

    vm.expectRevert(PoidhV3.NotSoloBounty.selector);
    poidh.cancelSoloBounty(0);

    _createSolo(1 ether);
    vm.prank(contributor);
    vm.expectRevert(PoidhV3.WrongCaller.selector);
    poidh.cancelSoloBounty(1);
  }

  function test_claimRefundFromCancelledOpenBounty_reverts_if_not_cancelled() public {
    _createOpen(1 ether);

    vm.prank(contributor);
    vm.expectRevert(PoidhV3.NotCancelledOpenBounty.selector);
    poidh.claimRefundFromCancelledOpenBounty(0);
  }
}

