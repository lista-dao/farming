// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import { IStrategy } from "./interfaces/IStrategy.sol";
import { IWombatPool } from "./interfaces/IWombatPool.sol";
import { IPancakeRouter02 } from "./interfaces/IPancakeRouter02.sol";
import { IHarvesttablePoolHelper } from "./interfaces/IHarvesttablePoolHelper.sol";

// solhint-disable max-states-count
contract MagpieStrategy is
  IStrategy,
  OwnableUpgradeable,
  ReentrancyGuardUpgradeable,
  PausableUpgradeable
{
  using SafeERC20Upgradeable for IERC20Upgradeable;

  event AutoharvestChanged(bool value);
  event MinEarnAmountChanged(uint256 indexed oldAmount, uint256 indexed newAmount);

  uint256 public pid;
  address public farmContractAddress;
  address public want;
  address public hay;
  address public wom;
  address public wombatPool;
  address public router;
  address public helioFarming;

  bool public enableAutoHarvest;

  address[] public earnedToHayPath;

  uint256 internal _wantLockedTotal;
  uint256 public sharesTotal;

  uint256 public minEarnAmount;
  uint256 public constant MIN_EARN_AMOUNT_LL = 10**10;

  uint256 public slippageFactor;
  uint256 public constant SLIPPAGE_FACTOR_UL = 995;
  uint256 public constant SLIPPAGE_FACTOR_MAX = 1000;

  modifier onlyHelioFarming() {
    require(msg.sender == helioFarming, "!helio Farming");
    _;
  }

  function initialize(
    uint256 _pid,
    uint256 _minEarnAmount,
    bool _enableAutoHarvest,
    address[] memory _addresses,
    // 0 address _farmContractAddress,
    // 1 address _want,
    // 2 address _cake,
    // 3 address _cake,
    // 4 address _wombatPool,
    // 5 address _router,
    // 6 address _helioFarming,
    address[] memory _earnedToHayPath
  ) public initializer {
    __Ownable_init();
    __ReentrancyGuard_init();
    __Pausable_init();
    require(_minEarnAmount >= MIN_EARN_AMOUNT_LL, "min earn amount is too low");
    slippageFactor = 950;
    pid = _pid;
    minEarnAmount = _minEarnAmount;
    farmContractAddress = _addresses[0];
    want = _addresses[1];
    hay = _addresses[2];
    wom = _addresses[3];
    wombatPool = _addresses[4];
    router = _addresses[5];
    helioFarming = _addresses[6];
    enableAutoHarvest = _enableAutoHarvest;
    earnedToHayPath = _earnedToHayPath;
  }

  function inCaseTokensGetStuck(
    address _token,
    uint256 _amount,
    address _to
  ) public virtual onlyOwner {
    require(_token != wom, "!safe");
    require(_token != hay, "!safe");
    require(_token != want, "!safe");
    IERC20Upgradeable(_token).safeTransfer(_to, _amount);
  }

  function pause() public virtual onlyOwner {
    _pause();
  }

  function unpause() public virtual onlyOwner {
    _unpause();
  }

  // Receives new deposits from user
  function deposit(address, uint256 _wantAmt)
    public
    virtual
    override
    onlyHelioFarming
    whenNotPaused
    returns (uint256)
  {
    if (enableAutoHarvest) {
      _harvest();
    }
    IERC20Upgradeable(want).safeTransferFrom(address(msg.sender), address(this), _wantAmt);

    uint256 sharesAdded = _wantAmt;

    uint256 sharesTotalLocal = sharesTotal;
    uint256 wantLockedTotalLocal = _wantLockedTotal;

    if (wantLockedTotalLocal > 0 && sharesTotalLocal > 0) {
      sharesAdded = (_wantAmt * sharesTotalLocal) / wantLockedTotalLocal;
    }
    sharesTotal = sharesTotalLocal + sharesAdded;

    _farm();

    return sharesAdded;
  }

  function withdraw(address, uint256 _wantAmt)
    public
    virtual
    override
    onlyHelioFarming
    nonReentrant
    returns (uint256)
  {
    require(_wantAmt > 0, "_wantAmt <= 0");

    if (enableAutoHarvest) {
      _harvest();
    }

    uint256 sharesRemoved = (_wantAmt * sharesTotal) / _wantLockedTotal;

    uint256 sharesTotalLocal = sharesTotal;
    if (sharesRemoved > sharesTotalLocal) {
      sharesRemoved = sharesTotalLocal;
    }
    sharesTotal = sharesTotalLocal - sharesRemoved;

    _unfarm(_wantAmt);

    uint256 wantAmt = IERC20Upgradeable(want).balanceOf(address(this));
    if (_wantAmt > wantAmt) {
      _wantAmt = wantAmt;
    }

    if (_wantLockedTotal < _wantAmt) {
      _wantAmt = _wantLockedTotal;
    }

    _wantLockedTotal -= _wantAmt;

    IERC20Upgradeable(want).safeTransfer(helioFarming, _wantAmt);

    return sharesRemoved;
  }

  function farm() public virtual nonReentrant {
    _farm();
  }

  function _farm() internal virtual {
    uint256 wantAmt = IERC20Upgradeable(want).balanceOf(address(this));
    _wantLockedTotal += wantAmt;
    IERC20Upgradeable(want).safeIncreaseAllowance(farmContractAddress, wantAmt);

    IHarvesttablePoolHelper(farmContractAddress).depositLP(wantAmt);
  }

  function _unfarm(uint256 _wantAmt) internal virtual {
    IHarvesttablePoolHelper(farmContractAddress).withdraw(
      _wantAmt,
      (_wantAmt * slippageFactor) / SLIPPAGE_FACTOR_MAX
    );
  }

  function _getRewards() internal virtual {
    IHarvesttablePoolHelper(farmContractAddress).depositLP(0);
  }

  // 1. Harvest farm tokens
  // 2. Converts farm tokens into want tokens
  // 3. Deposits want tokens
  function harvest() public virtual nonReentrant whenNotPaused {
    _harvest();
  }

  // 1. Harvest farm tokens
  // 2. Converts farm tokens into want tokens
  // 3. Deposits want tokens
  function _harvest() internal virtual {
    // Harvest farm tokens
    _getRewards();

    // Converts farm tokens into want tokens
    uint256 earnedHayAmt = IERC20Upgradeable(hay).balanceOf(address(this));
    uint256 earnedWomAmt = IERC20Upgradeable(wom).balanceOf(address(this));
    uint256[] memory amounts = IPancakeRouter02(router).getAmountsOut(
      earnedWomAmt,
      earnedToHayPath
    );
    uint256 hayEarned = earnedHayAmt + amounts[amounts.length - 1];

    if (hayEarned < minEarnAmount) {
      return;
    }

    IERC20Upgradeable(wom).safeApprove(router, 0);
    IERC20Upgradeable(wom).safeIncreaseAllowance(router, earnedWomAmt);

    // Swap half earned to token1
    _safeSwap(
      router,
      earnedWomAmt,
      slippageFactor,
      earnedToHayPath,
      address(this),
      block.timestamp + 500
    );

    // Get want tokens, ie. add liquidity
    earnedHayAmt = IERC20Upgradeable(hay).balanceOf(address(this));
    IERC20Upgradeable(hay).safeIncreaseAllowance(wombatPool, earnedHayAmt);
    IWombatPool(wombatPool).deposit(
      hay,
      earnedHayAmt,
      (earnedHayAmt * slippageFactor) / SLIPPAGE_FACTOR_MAX,
      address(this),
      block.timestamp,
      false
    );

    _farm();
  }

  function _safeSwap(
    address _uniRouterAddress,
    uint256 _amountIn,
    uint256 _slippageFactor,
    address[] memory _path,
    address _to,
    uint256 _deadline
  ) internal virtual {
    uint256[] memory amounts = IPancakeRouter02(_uniRouterAddress).getAmountsOut(_amountIn, _path);
    uint256 amountOut = amounts[amounts.length - 1];

    IPancakeRouter02(_uniRouterAddress).swapExactTokensForTokensSupportingFeeOnTransferTokens(
      _amountIn,
      (amountOut * _slippageFactor) / SLIPPAGE_FACTOR_MAX,
      _path,
      _to,
      _deadline
    );
  }

  function setAutoHarvest(bool _value) external onlyOwner {
    enableAutoHarvest = _value;
    emit AutoharvestChanged(_value);
  }

  function setSlippageFactor(uint256 _slippageFactor) external onlyOwner {
    require(_slippageFactor <= SLIPPAGE_FACTOR_UL, "slippageFactor too high");
    slippageFactor = _slippageFactor;
  }

  function setMinEarnAmount(uint256 _minEarnAmount) external onlyOwner {
    require(_minEarnAmount >= MIN_EARN_AMOUNT_LL, "min earn amount is too low");
    minEarnAmount = _minEarnAmount;
    emit MinEarnAmountChanged(minEarnAmount, _minEarnAmount);
  }

  function wantLockedTotal() external view virtual override returns (uint256) {
    return _wantLockedTotal;
  }
}
