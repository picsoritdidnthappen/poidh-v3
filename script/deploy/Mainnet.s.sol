// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployBaseScript} from "../DeployBase.s.sol";

contract DeployMainnet is DeployBaseScript {
  address constant TREASURY = 0x293e70B7e1EC808358461f5d6247cdb877B6DeD2;

  function run() external {
    DeployConfig memory cfg = _loadCommonConfig();
    cfg.treasury = TREASURY;
    cfg.minBountyAmount = 0.001 ether;
    cfg.minContribution = 0.000_01 ether;
    _deploy(cfg);
  }
}
