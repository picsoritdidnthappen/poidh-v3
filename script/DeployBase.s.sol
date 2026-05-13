// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {PoidhV3} from "../src/PoidhV3.sol";
import {PoidhClaimNFT} from "../src/PoidhClaimNFT.sol";

abstract contract DeployBaseScript is Script {
  struct DeployConfig {
    address treasury;
    uint256 startClaimIndex;
    string nftName;
    string nftSymbol;
    uint256 minBountyAmount;
    uint256 minContribution;
  }

  event Deployment(
    address indexed poidh,
    address indexed nft,
    address treasury,
    uint256 startClaimIndex,
    uint256 minBountyAmount,
    uint256 minContribution
  );

  function _loadCommonConfig() internal view returns (DeployConfig memory cfg) {
    cfg.treasury = vm.envOr("POIDH_TREASURY", address(0));
    cfg.startClaimIndex = vm.envOr("POIDH_START_CLAIM_INDEX", uint256(1));
    cfg.nftName = vm.envOr("POIDH_NFT_NAME", string("poidh claims v3"));
    cfg.nftSymbol = vm.envOr("POIDH_NFT_SYMBOL", string("POIDH3"));
    cfg.minBountyAmount = vm.envOr("POIDH_MIN_BOUNTY_AMOUNT", uint256(0.0001 ether));
    cfg.minContribution = vm.envOr("POIDH_MIN_CONTRIBUTION", uint256(0.0001 ether));
  }

  function _deploy(DeployConfig memory cfg) internal {
    uint256 deployerPk = vm.envOr("DEPLOYER_PK", uint256(0));
    if (deployerPk != 0) {
      vm.startBroadcast(deployerPk);
    } else {
      vm.startBroadcast();
    }

    address deployer = deployerPk != 0 ? vm.addr(deployerPk) : msg.sender;
    uint256 nonce = vm.getNonce(deployer);
    address predictedPoidh = vm.computeCreateAddress(deployer, nonce + 1);

    PoidhClaimNFT nft = new PoidhClaimNFT(cfg.nftName, cfg.nftSymbol, predictedPoidh);
    PoidhV3 poidh = new PoidhV3(
      address(nft),
      cfg.treasury,
      cfg.startClaimIndex,
      cfg.minBountyAmount,
      cfg.minContribution
    );

    emit Deployment(
      address(poidh),
      address(nft),
      cfg.treasury,
      cfg.startClaimIndex,
      cfg.minBountyAmount,
      cfg.minContribution
    );

    console2.log("PoidhClaimNFT:", address(nft));
    console2.log("PoidhV3:", address(poidh));
    console2.log("Treasury:", cfg.treasury);
    console2.log("StartClaimIndex:", cfg.startClaimIndex);
    console2.log("MinBountyAmount:", cfg.minBountyAmount);
    console2.log("MinContribution:", cfg.minContribution);

    vm.stopBroadcast();
  }
}
