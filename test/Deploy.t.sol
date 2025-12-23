// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {PoidhV3} from "../src/PoidhV3.sol";
import {PoidhClaimNFT} from "../src/PoidhClaimNFT.sol";

contract DeployScriptTest is Test {
    function test_run_deploys_and_wires_contracts() public {
        address treasury = makeAddr("treasury");

        vm.setEnv("POIDH_TREASURY", vm.toString(treasury));
        vm.setEnv("POIDH_START_CLAIM_INDEX", "1");

        vm.recordLogs();
        Deploy d = new Deploy();
        d.run();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("PoidhSet(address,address)");

        address nftAddr;
        address payable poidhAddr;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length == 3 && logs[i].topics[0] == sig) {
                nftAddr = logs[i].emitter;
                poidhAddr = payable(address(uint160(uint256(logs[i].topics[2]))));
                break;
            }
        }

        assertTrue(nftAddr != address(0));
        assertTrue(poidhAddr != address(0));

        PoidhClaimNFT nft = PoidhClaimNFT(nftAddr);
        PoidhV3 poidh = PoidhV3(poidhAddr);

        assertEq(nft.poidh(), poidhAddr);
        assertEq(poidh.treasury(), treasury);
        assertEq(address(poidh.poidhNft()), nftAddr);
        assertEq(poidh.claimCounter(), 1);
    }
}
