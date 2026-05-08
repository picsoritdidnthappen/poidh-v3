// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../../src/PoidhV3.sol";
import "../../src/PoidhClaimNFT.sol";

contract MainnetDeploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address treasury = 0x293e70B7e1EC808358461f5d6247cdb877B6DeD2;

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy NFT
        PoidhClaimNFT poidhNft = new PoidhClaimNFT("poidh v3", "POIDH", treasury);

        // 2. Deploy V3
        // We change the 0s to 1 (which is 1 wei, the smallest possible amount)
        // Arguments: NFT, Treasury, StartIndex, MinBounty, MinContribute
        new PoidhV3(address(poidhNft), treasury, 1, 1, 1);

        vm.stopBroadcast();
    }
}
root@localhost:~/poidh-v3#
