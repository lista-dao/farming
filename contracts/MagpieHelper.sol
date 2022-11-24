// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { IFarmingV2 } from "./interfaces/IFarmingV2.sol";
import { IWombatPool } from "./interfaces/IWombatPool.sol";

// hay: 0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5
// hay-lp: 0x1fa71DF4b344ffa5755726Ea7a9a56fbbEe0D38b

contract MagpieHelper is Initializable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  uint256 public pid;
  address public token;
  address public tokenLp;
  address public farming;
  address public wombatPool;

  function initialize(
    uint256 _pid,
    address _token,
    address _tokenLp,
    address _farming,
    address _wombatPool
  ) public initializer {
    pid = _pid;
    token = _token;
    tokenLp = _tokenLp;
    farming = _farming;
    wombatPool = _wombatPool;
    IERC20Upgradeable(token).approve(wombatPool, type(uint256).max);
  }

  function deposit(uint256 _amount, uint256 _minimumLiquidity) external {
    address user = msg.sender;
    IERC20Upgradeable(token).safeTransferFrom(user, address(this), _amount);
    IWombatPool(wombatPool).deposit(
      token,
      _amount,
      _minimumLiquidity,
      address(this),
      block.timestamp,
      false
    );

    IFarmingV2(farming).deposit(
      pid,
      IERC20Upgradeable(tokenLp).balanceOf(address(this)),
      false,
      user
    );
  }

  function withdraw(uint256 _amount, uint256 _minimumLiquidity) external {
    address user = msg.sender;
    IFarmingV2(farming).withdrawFor(pid, _amount, false, user, address(this));

    IWombatPool(wombatPool).withdraw(
      token,
      IERC20Upgradeable(tokenLp).balanceOf(address(this)),
      _minimumLiquidity,
      user,
      block.timestamp
    );
  }

  function depositLp(uint256 _amount) external {
    address user = msg.sender;
    IERC20Upgradeable(tokenLp).safeTransferFrom(user, address(this), _amount);

    IFarmingV2(farming).deposit(
      pid,
      IERC20Upgradeable(tokenLp).balanceOf(address(this)),
      false,
      user
    );
  }

  function withdrawLp(uint256 _amount) external {
    address user = msg.sender;
    IERC20Upgradeable(tokenLp).safeTransferFrom(user, address(this), _amount);

    IFarmingV2(farming).withdrawFor(pid, _amount, false, user, user);
  }
}
