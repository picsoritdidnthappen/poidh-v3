// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PoidhV3} from "../src/PoidhV3.sol";
import {PoidhClaimNFT} from "../src/PoidhClaimNFT.sol";

contract PoidhV3FuzzTest is Test {
  PoidhV3 poidh;
  PoidhClaimNFT nft;

  address treasury;
  address issuer;
  address claimant;
  address contributor;

  function setUp() public {
    vm.txGasPrice(0);

    treasury = makeAddr("treasury");
    issuer = makeAddr("issuer");
    claimant = makeAddr("claimant");
    contributor = makeAddr("contributor");

    nft = new PoidhClaimNFT("poidh claims v3", "POIDH3");
    poidh = new PoidhV3(address(nft), treasury, 1);
    nft.setPoidh(address(poidh));

    vm.deal(issuer, 10_000 ether);
    vm.deal(claimant, 10_000 ether);
    vm.deal(contributor, 10_000 ether);
    vm.deal(treasury, 0);
  }

  function testFuzz_solo_acceptClaim_feeAccounting(uint96 bountyAmountRaw) public {
    uint256 min = poidh.MIN_BOUNTY_AMOUNT();
    uint256 bountyAmount = bound(uint256(bountyAmountRaw), min, 100 ether);

    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: bountyAmount}("solo", "desc");

    vm.prank(claimant);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");

    vm.prank(issuer, issuer);
    poidh.acceptClaim(0, 1);

    uint256 expectedFee = (bountyAmount * poidh.FEE_BPS()) / poidh.BPS_DENOM();
    uint256 expectedPayout = bountyAmount - expectedFee;

    assertEq(poidh.pendingWithdrawals(claimant), expectedPayout);
    assertEq(poidh.pendingWithdrawals(treasury), expectedFee);
    assertEq(nft.ownerOf(1), issuer);
  }

  function testFuzz_open_vote_outcome_matches_majority(
    uint96 issuerAmountRaw,
    uint96 contribAmountRaw,
    bool voteYes
  ) public {
    uint256 min = poidh.MIN_BOUNTY_AMOUNT();
    uint256 minContrib = poidh.MIN_CONTRIBUTION();
    uint256 issuerAmount = bound(uint256(issuerAmountRaw), min, 25 ether);
    uint256 contribAmount = bound(uint256(contribAmountRaw), minContrib, 25 ether);

    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: issuerAmount}("open", "desc");

    vm.prank(contributor, contributor);
    poidh.joinOpenBounty{value: contribAmount}(0);

    vm.prank(claimant);
    poidh.createClaim(0, "claim", "desc", "ipfs://x");

    vm.prank(issuer, issuer);
    poidh.submitClaimForVote(0, 1);

    vm.prank(contributor);
    poidh.voteClaim(0, voteYes);

    vm.warp(block.timestamp + poidh.votingPeriod());
    poidh.resolveVote(0);

    uint256 yes = issuerAmount + (voteYes ? contribAmount : 0);
    uint256 no = voteYes ? 0 : contribAmount;
    bool passed = yes > ((yes + no) / 2);

    uint256 total = issuerAmount + contribAmount;
    uint256 expectedFee = (total * poidh.FEE_BPS()) / poidh.BPS_DENOM();
    uint256 expectedPayout = total - expectedFee;

    if (passed) {
      assertEq(poidh.pendingWithdrawals(claimant), expectedPayout);
      assertEq(poidh.pendingWithdrawals(treasury), expectedFee);
      assertEq(nft.ownerOf(1), issuer);
    } else {
      assertEq(poidh.pendingWithdrawals(claimant), 0);
      assertEq(poidh.pendingWithdrawals(treasury), 0);
      assertEq(nft.ownerOf(1), address(poidh)); // escrow
      assertEq(poidh.bountyCurrentVotingClaim(0), 0);
    }
  }
}

