// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {PoidhV3} from "../src/PoidhV3.sol";
import {PoidhClaimNFT} from "../src/PoidhClaimNFT.sol";

contract Deploy is Script {
    function run() external {
        // ---- Configure ----
        address treasury = vm.envAddress("POIDH_TREASURY");
        uint256 startClaimIndex = vm.envUint("POIDH_START_CLAIM_INDEX"); // must be >= 1 (0 is reserved sentinel)

        vm.startBroadcast();

        // 1) Deploy NFT
        PoidhClaimNFT nft = new PoidhClaimNFT("poidh claims v3", "POIDH3");

        // 2) Deploy PoidhV3
        PoidhV3 poidh = new PoidhV3(address(nft), treasury, startClaimIndex);

        // 3) Wire NFT minter
        nft.setPoidh(address(poidh));

        // 4) Transfer ownerships to multisig (optional)
        // address multisig = vm.envAddress("POIDH_MULTISIG");
        // poidh.transferOwnership(multisig);
        // nft.transferOwnership(multisig);

        vm.stopBroadcast();
    }
}
