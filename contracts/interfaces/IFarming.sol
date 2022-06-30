// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { IStrategy } from "./IStrategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFarming {
  function poolInfo(uint256 pid)
    external
    view
    returns (
      IERC20,
      IStrategy,
      uint256,
      uint256,
      uint256
    );

  function addPool(
    address token,
    address strategy,
    bool withUpdate
  ) external returns (uint256);

  function rewardToken() external returns (IERC20);
}
