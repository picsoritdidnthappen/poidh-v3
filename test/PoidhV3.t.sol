// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PoidhV3} from "../src/PoidhV3.sol";
import {PoidhClaimNFT} from "../src/PoidhClaimNFT.sol";

contract PoidhV3Test is Test {
    PoidhV3 poidh;
    PoidhClaimNFT nft;

    address treasury = address(0xBEEF);
    address issuer = address(0xA11CE);
    address claimant = address(0xB0B);
    address contributor = address(0xCAFE);

    function setUp() public {
        nft = new PoidhClaimNFT("poidh claims v3", "POIDH3");
        poidh = new PoidhV3(address(nft), treasury, 1);
        nft.setPoidh(address(poidh));

        vm.deal(issuer, 10 ether);
        vm.deal(claimant, 10 ether);
        vm.deal(contributor, 10 ether);
    }

    function test_soloBounty_acceptClaim_paysOutViaPending() public {
        vm.prank(issuer);
        poidh.createSoloBounty{value: 1 ether}("solo", "desc");

        vm.prank(claimant);
        poidh.createClaim(0, "claim", "desc", "ipfs://x");

        vm.prank(issuer);
        poidh.acceptClaim(0, 1);

        // payout = 0.975 ether, fee = 0.025 ether
        assertEq(poidh.pendingWithdrawals(claimant), 0.975 ether);
        assertEq(poidh.pendingWithdrawals(treasury), 0.025 ether);
        // NFT transferred to issuer
        assertEq(nft.ownerOf(1), issuer);
    }

    function test_openBounty_voting_flow() public {
        vm.prank(issuer);
        poidh.createOpenBounty{value: 1 ether}("open", "desc");

        vm.prank(contributor);
        poidh.joinOpenBounty{value: 1 ether}(0);

        vm.prank(claimant);
        poidh.createClaim(0, "claim", "desc", "ipfs://x");

        vm.prank(issuer);
        poidh.submitClaimForVote(0, 1);

        // contributor votes yes
        vm.prank(contributor);
        poidh.voteClaim(0, true);

        // warp past deadline
        vm.warp(block.timestamp + 2 days + 1);

        poidh.resolveVote(0);

        assertEq(nft.ownerOf(1), issuer);
        assertEq(poidh.pendingWithdrawals(claimant), 1.95 ether); // 2 ether * (1 - 2.5%)
        assertEq(poidh.pendingWithdrawals(treasury), 0.05 ether);
    }

    function test_cancelOpenBounty_refund_claim() public {
        vm.prank(issuer);
        poidh.createOpenBounty{value: 1 ether}("open", "desc");

        vm.prank(contributor);
        poidh.joinOpenBounty{value: 1 ether}(0);

        vm.prank(issuer);
        poidh.cancelOpenBounty(0);

        // issuer refunded automatically
        assertEq(poidh.pendingWithdrawals(issuer), 1 ether);

        // contributor claims
        vm.prank(contributor);
        poidh.claimRefundFromCancelledOpenBounty(0);
        assertEq(poidh.pendingWithdrawals(contributor), 1 ether);
    }
}
