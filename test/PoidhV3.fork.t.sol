// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PoidhV3} from "../src/PoidhV3.sol";
import {PoidhClaimNFT} from "../src/PoidhClaimNFT.sol";

contract PoidhV3ForkTest is Test {
    string internal forkUrl;

    function setUp() public {
        forkUrl = vm.envOr("FORK_URL", string(""));
        if (bytes(forkUrl).length == 0) {
            vm.skip(true, "FORK_URL not set");
        }

        uint256 forkBlock = vm.envOr("FORK_BLOCK", uint256(0));
        if (forkBlock == 0) {
            vm.createSelectFork(forkUrl);
        } else {
            vm.createSelectFork(forkUrl, forkBlock);
        }
    }

    function testFork_smoke_openBounty_voting_flow() public {
        vm.txGasPrice(0);

        address treasury = address(0xBEEF);
        address issuer = makeAddr("issuer");
        address claimant = makeAddr("claimant");
        address contributor = makeAddr("contributor");

        vm.deal(issuer, 10 ether);
        vm.deal(claimant, 10 ether);
        vm.deal(contributor, 10 ether);

        PoidhClaimNFT nft = new PoidhClaimNFT("poidh claims v3", "POIDH3");
        PoidhV3 poidh = new PoidhV3(address(nft), treasury, 1);
        nft.setPoidh(address(poidh));

        vm.prank(issuer);
        poidh.createOpenBounty{value: 1 ether}("open", "desc");

        vm.prank(contributor);
        poidh.joinOpenBounty{value: 1 ether}(0);

        vm.prank(claimant);
        poidh.createClaim(0, "claim", "desc", "ipfs://x");

        vm.prank(issuer);
        poidh.submitClaimForVote(0, 1);

        vm.prank(contributor);
        poidh.voteClaim(0, true);

        vm.warp(block.timestamp + poidh.votingPeriod());
        poidh.resolveVote(0);

        assertEq(nft.ownerOf(1), issuer);
    }
}

