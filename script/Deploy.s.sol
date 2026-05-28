// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployBaseScript} from "./DeployBase.s.sol";

contract Deploy is DeployBaseScript {
  function run() external {
    DeployConfig memory cfg = _loadCommonConfig();
    _deploy(cfg);
  }
}
