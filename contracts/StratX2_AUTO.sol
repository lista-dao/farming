// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { StratX2 } from "./StratX2.sol";

// solhint-disable-next-line contract-name-camelcase
contract StratX2_AUTO is StratX2 {
  using SafeERC20 for IERC20;

  address[] public users;
  mapping(address => uint256) public userLastDepositedTimestamp;
  uint256 public minTimeToWithdraw; // 604800 = 1 week
  uint256 public minTimeToWithdrawUL = 1209600; // 2 weeks

  event MinTimeToWithdrawChanged(uint256 oldMinTimeToWithdraw, uint256 newMinTimeToWithdraw);

  event Earned(uint256 oldWantLockedTotal, uint256 newWantLockedTotal);

  constructor(
    uint256 _pid,
    address[] memory _addresses,
    bool[] memory _boolData,
    uint256[] memory _uintData,
    address[] memory _earnedToAUTOPath,
    address[] memory _earnedToToken0Path,
    address[] memory _earnedToToken1Path,
    address[] memory _token0ToEarnedPath,
    address[] memory _token1ToEarnedPath
  ) {
    pid = _pid;
    _setupAddresses(_addresses);
    _setupBoolData(_boolData);
    _setupUintData(_uintData);

    earnedToAUTOPath = _earnedToAUTOPath;
    earnedToToken0Path = _earnedToToken0Path;
    earnedToToken1Path = _earnedToToken1Path;
    token0ToEarnedPath = _token0ToEarnedPath;
    token1ToEarnedPath = _token1ToEarnedPath;

    transferOwnership(autoFarmAddress);
  }

  // to avoid stack too deep errors
  function _setupAddresses(address[] memory _addresses) internal {
    wbnbAddress = _addresses[0];
    govAddress = _addresses[1];
    autoFarmAddress = _addresses[2];
    AUTOAddress = _addresses[3];

    wantAddress = _addresses[4];
    token0Address = _addresses[5];
    token1Address = _addresses[6];
    earnedAddress = _addresses[7];

    farmContractAddress = _addresses[8];
    uniRouterAddress = _addresses[9];
    rewardsAddress = _addresses[10];
    buyBackAddress = _addresses[11];
  }

  // to avoid stack too deep errors
  function _setupBoolData(bool[] memory _boolData) internal {
    isCAKEStaking = _boolData[0];
    isSameAssetDeposit = _boolData[1];
    isAutoComp = _boolData[2];
  }

  // to avoid stack too deep errors
  function _setupUintData(uint256[] memory _uintData) internal {
    controllerFee = _uintData[0];
    buyBackRate = _uintData[1];
    entranceFeeFactor = _uintData[2];
    withdrawFeeFactor = _uintData[3];
    minTimeToWithdraw = _uintData[4];
  }

  function deposit(address _userAddress, uint256 _wantAmt)
    public
    override
    onlyOwner
    nonReentrant
    whenNotPaused
    returns (uint256)
  {
    if (userLastDepositedTimestamp[_userAddress] == 0) {
      users.push(_userAddress);
    }
    userLastDepositedTimestamp[_userAddress] = block.timestamp;

    IERC20(wantAddress).safeTransferFrom(address(msg.sender), address(this), _wantAmt);

    uint256 sharesAdded = _wantAmt;
    if (wantLockedTotal > 0 && sharesTotal > 0) {
      sharesAdded =
        (_wantAmt * sharesTotal * entranceFeeFactor) /
        wantLockedTotal /
        entranceFeeFactorMax;
    }
    sharesTotal += sharesAdded;

    wantLockedTotal = IERC20(AUTOAddress).balanceOf(address(this));

    return sharesAdded;
  }

  function withdraw(address _userAddress, uint256 _wantAmt)
    public
    override
    onlyOwner
    nonReentrant
    returns (uint256)
  {
    require(
      userLastDepositedTimestamp[_userAddress] + minTimeToWithdraw < block.timestamp,
      "too early!"
    );

    require(_wantAmt > 0, "_wantAmt <= 0");

    uint256 sharesRemoved = (_wantAmt * sharesTotal) / wantLockedTotal;
    if (sharesRemoved > sharesTotal) {
      sharesRemoved = sharesTotal;
    }
    sharesTotal -= sharesRemoved;

    if (withdrawFeeFactor < withdrawFeeFactorMax) {
      _wantAmt = (_wantAmt * withdrawFeeFactor) / withdrawFeeFactorMax;
    }

    // if (isAutoComp) {
    //     _unfarm(_wantAmt);
    // }

    uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
    if (_wantAmt > wantAmt) {
      _wantAmt = wantAmt;
    }

    if (wantLockedTotal < _wantAmt) {
      _wantAmt = wantLockedTotal;
    }

    wantLockedTotal -= _wantAmt;

    IERC20(wantAddress).safeTransfer(autoFarmAddress, _wantAmt);

    return sharesRemoved;
  }

  // solhint-disable-next-line no-empty-blocks
  function _farm() internal override {}

  // solhint-disable-next-line no-empty-blocks
  function _unfarm(uint256 _wantAmt) internal override {}

  function earn() public override nonReentrant whenNotPaused {
    // require(isAutoComp, "!isAutoComp");
    if (onlyGov) {
      require(msg.sender == govAddress, "!gov");
    }

    if (earnedAddress == wbnbAddress) {
      _wrapBNB();
    }

    uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

    // earnedAmt = distributeFees(earnedAmt);   // Not need to distribute fees again. Already done.

    IERC20(earnedAddress).safeApprove(uniRouterAddress, 0);
    IERC20(earnedAddress).safeIncreaseAllowance(uniRouterAddress, earnedAmt);
    _safeSwap(
      uniRouterAddress,
      earnedAmt,
      slippageFactor,
      earnedToAUTOPath,
      address(this),
      block.timestamp + 600
    );

    lastEarnBlock = block.number;

    uint256 wantLockedTotalOld = wantLockedTotal;

    wantLockedTotal = IERC20(AUTOAddress).balanceOf(address(this));

    emit Earned(wantLockedTotalOld, wantLockedTotal);
  }

  function setMinTimeToWithdraw(uint256 newMinTimeToWithdraw) public onlyAllowGov {
    require(newMinTimeToWithdraw <= minTimeToWithdrawUL, "too high");
    emit MinTimeToWithdrawChanged(minTimeToWithdraw, newMinTimeToWithdraw);
    minTimeToWithdraw = newMinTimeToWithdraw;
  }

  function userLength() public view returns (uint256) {
    return users.length;
  }

  // solhint-disable-next-line no-empty-blocks
  receive() external payable {}
}
