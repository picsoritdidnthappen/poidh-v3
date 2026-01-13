// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployBaseScript} from "../DeployBase.s.sol";

contract DeployBaseSepolia is DeployBaseScript {
  // Deployer address as treasury for testnet
  address constant TREASURY = 0x50f57a0A3A563321619c57733154F8D8D3e4082b;

  function run() external {
    DeployConfig memory cfg = _loadCommonConfig();
    cfg.treasury = TREASURY;
    cfg.minBountyAmount = 0.001 ether;
    cfg.minContribution = 0.000_01 ether;
    _deploy(cfg);
  }
}
