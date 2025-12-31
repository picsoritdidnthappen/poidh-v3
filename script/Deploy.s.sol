// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {PoidhV3} from "../src/PoidhV3.sol";
import {PoidhClaimNFT} from "../src/PoidhClaimNFT.sol";

contract Deploy is Script {
  function run() external {
    // ---- Configure ----
    address treasury = vm.envAddress("POIDH_TREASURY");
    uint256 startClaimIndex = vm.envUint("POIDH_START_CLAIM_INDEX"); // must be >= 1 (0 is reserved)

    string memory nftName = vm.envOr("POIDH_NFT_NAME", string("poidh claims v3"));
    string memory nftSymbol = vm.envOr("POIDH_NFT_SYMBOL", string("POIDH3"));

    address multisig = vm.envOr("POIDH_MULTISIG", address(0)); // optional

    vm.startBroadcast();

    // 1) Deploy NFT
    PoidhClaimNFT nft = new PoidhClaimNFT(nftName, nftSymbol);

    // 2) Deploy PoidhV3
    PoidhV3 poidh = new PoidhV3(address(nft), treasury, startClaimIndex);

    // 3) Wire NFT minter
    nft.setPoidh(address(poidh));

    // 4) Transfer NFT ownership to multisig (optional; recommended)
    if (multisig != address(0)) nft.transferOwnership(multisig);

    console2.log("PoidhClaimNFT:", address(nft));
    console2.log("PoidhV3:", address(poidh));
    console2.log("Treasury:", treasury);
    console2.log("StartClaimIndex:", startClaimIndex);
    if (multisig != address(0)) console2.log("Multisig (ownership pending):", multisig);

    vm.stopBroadcast();
  }
}
