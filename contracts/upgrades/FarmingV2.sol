// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import { Farming } from "../Farming.sol";
import { IStrategy } from "../interfaces/IStrategy.sol";
import { IFarmingV2, IFarming } from "../interfaces/IFarmingV2.sol";
import { IIncentiveVoting } from "../interfaces/IIncentiveVoting.sol";

contract FarmingV2 is Farming, IFarmingV2 {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  event HelperWhitelist(address indexed helper, bool indexed whitelisted);

  mapping(address => bool) public whitelistedHelpers;

  function withdraw(
    uint256 _pid,
    uint256 _wantAmt,
    bool _claimRewards
  ) public virtual override(Farming, IFarming) nonReentrant returns (uint256) {
    return _withdraw(_pid, _wantAmt, _claimRewards, msg.sender, msg.sender);
  }

  function withdrawFor(
    uint256 _pid,
    uint256 _wantAmt,
    bool _claimRewards,
    address _userAddress,
    address _receiver
  ) external nonReentrant returns (uint256) {
    require(whitelistedHelpers[msg.sender], "caller is not whitelisted");
    require(!blockThirdPartyActions[_userAddress], "third party actions are blocked by user");
    return _withdraw(_pid, _wantAmt, _claimRewards, _userAddress, _receiver);
  }

  function _withdraw(
    uint256 _pid,
    uint256 _wantAmt,
    bool _claimRewards,
    address _userAddress,
    address _receiver
  ) internal virtual returns (uint256) {
    require(_wantAmt > 0, "Cannot withdraw zero");
    uint256 accRewardPerShare = updatePool(_pid);
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_userAddress];

    uint256 sharesTotal = pool.strategy.sharesTotal();

    require(user.shares > 0, "user.shares is 0");
    require(sharesTotal > 0, "sharesTotal is 0");

    uint256 pending = (user.shares * accRewardPerShare) / 1e12 - user.rewardDebt;
    if (_claimRewards) {
      pending += user.claimable;
      user.claimable = 0;
      pending = _safeRewardTransfer(_userAddress, pending);
    } else if (pending > 0) {
      user.claimable += pending;
      pending = 0;
    }
    // Withdraw want tokens
    uint256 amount = (user.shares * pool.strategy.wantLockedTotal()) / sharesTotal;
    if (_wantAmt > amount) {
      _wantAmt = amount;
    }
    uint256 sharesRemoved = pool.strategy.withdraw(_userAddress, _wantAmt);

    if (sharesRemoved > user.shares) {
      user.shares = 0;
    } else {
      user.shares -= sharesRemoved;
    }

    uint256 wantBal = pool.token.balanceOf(address(this));
    if (wantBal < _wantAmt) {
      _wantAmt = wantBal;
    }
    user.rewardDebt = (user.shares * pool.accRewardPerShare) / 1e12;
    pool.token.safeTransfer(_receiver, _wantAmt);

    emit Withdraw(_userAddress, _pid, _wantAmt);
    return pending;
  }

  function whitelistHelper(address helper, bool whitelist) external onlyOwner {
    whitelistedHelpers[helper] = whitelist;
    emit HelperWhitelist(helper, whitelist);
  }
}
