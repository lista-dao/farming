// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { IFarming } from "./IFarming.sol";

interface IFarmingV2 is IFarming {
  function withdrawFor(
    uint256 _pid,
    uint256 _wantAmt,
    bool _claimRewards,
    address _userAddress,
    address _receiver
  ) external returns (uint256);
}
