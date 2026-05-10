// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PoidhV3} from "../../src/PoidhV3.sol";
import {PoidhClaimNFT} from "../../src/PoidhClaimNFT.sol";

contract DeployMainnet is Script {
    function run() external {
        address treasury = vm.envOr("POIDH_TREASURY", address(0x293e70B7e1EC808358461f5d6247cdb877B6DeD2));
        uint256 startClaimIndex = vm.envOr("POIDH_START_CLAIM_INDEX", uint256(1));
        uint256 minBountyAmount = vm.envOr("POIDH_MIN_BOUNTY_AMOUNT", uint256(1000000000000000));
        uint256 minContribution = vm.envOr("POIDH_MIN_CONTRIBUTION", uint256(10000000000000));
        string memory nftName = vm.envOr("POIDH_NFT_NAME", string("poidh claims v3"));
        string memory nftSymbol = vm.envOr("POIDH_NFT_SYMBOL", string("POIDH3"));

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        uint64 currentNonce = vm.getNonce(deployer);
        address predictedV3Address = vm.computeCreateAddress(deployer, currentNonce + 1);

        console.log("Deployer:", deployer);
        console.log("Current nonce:", currentNonce);
        console.log("Predicted V3 address:", predictedV3Address);

        PoidhClaimNFT poidhNft = new PoidhClaimNFT(
            nftName,
            nftSymbol,
            predictedV3Address
        );

        console.log("NFT deployed at:", address(poidhNft));

        PoidhV3 poidhV3 = new PoidhV3(
            address(poidhNft),
            treasury,
            startClaimIndex,
            minBountyAmount,
            minContribution
        );

        console.log("V3 deployed at:", address(poidhV3));

        require(address(poidhV3) == predictedV3Address, "Address prediction failed!");

        vm.stopBroadcast();

        console.log("=================================");
        console.log("Deployment Complete!");
        console.log("=================================");
        console.log("PoidhV3:", address(poidhV3));
        console.log("PoidhClaimNFT:", address(poidhNft));
        console.log("Treasury:", treasury);
        console.log("MIN_BOUNTY_AMOUNT:", minBountyAmount);
        console.log("MIN_CONTRIBUTION:", minContribution);
        console.log("=================================");
    }
}
