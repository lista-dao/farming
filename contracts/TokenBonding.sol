// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { ITokenBonding } from "./interfaces/ITokenBonding.sol";

contract TokenBonding is IERC20Metadata, ITokenBonding, Ownable, ReentrancyGuard {
  using SafeERC20 for IERC20;

  event TokenAdded(address indexed token, uint256 coefficient);
  event UnbondingRequest(address indexed token, uint256 amount, uint256 timestamp);

  string private constant NAME = "veHELIO";
  string private constant SYMBOL = "veHELIO";
  uint8 private constant DECIMALS = 18;
  // TODO: remove for mainnet
  uint256 private constant WEEK = 1 hours;
  // uint256 private constant WEEK = 1 weeks;
  uint256 private _totalSupply;
  uint256 private _totalWeight;

  struct TokenInfo {
    uint240 coefficient;
    uint16 index;
    uint256 totalStaked;
  }

  struct StakeInfo {
    uint256 staked;
    uint256 wantClaim;
    uint256 requestTime;
  }

  mapping(address => mapping(address => StakeInfo)) private _userStakeInfo;
  mapping(address => TokenInfo) private _tokenInfo;
  address[] private _tokens;

  uint256 public startTime;

  modifier isStarted() {
    require(block.timestamp > startTime, "Contract is not started yet");
    _;
  }

  constructor(
    uint256 startTime_,
    address[] memory tokens_,
    uint240[] memory coefficients_
  ) {
    require(
      (startTime_ / WEEK) * WEEK == startTime_ && startTime_ > block.timestamp,
      "!epoch week"
    );
    uint256 length = tokens_.length;
    require(length == coefficients_.length, "Not equal lengths");
    startTime = startTime_;
    for (uint16 i; i < length; ++i) {
      _tokenInfo[tokens_[i]] = TokenInfo({
        coefficient: coefficients_[i],
        index: i + 1,
        totalStaked: 0
      });
      _tokens.push(tokens_[i]);
      emit TokenAdded(tokens_[i], coefficients_[i]);
    }
  }

  function name() external pure returns (string memory) {
    return NAME;
  }

  function symbol() external pure returns (string memory) {
    return SYMBOL;
  }

  function decimals() external pure returns (uint8) {
    return DECIMALS;
  }

  function totalSupply() external view returns (uint256) {
    return _totalSupply;
  }

  function balanceOf(address user_) external view returns (uint256) {
    uint256 userBalance_;
    unchecked {
      for (uint256 i; i < _tokens.length; ++i) {
        userBalance_ +=
          ((uint256(_userStakeInfo[user_][_tokens[i]].staked) +
            _userStakeInfo[user_][_tokens[i]].wantClaim) * _tokenInfo[_tokens[i]].coefficient) /
          10**18;
      }
    }
    return userBalance_;
  }

  function userWeight(address user_) external view returns (uint256) {
    uint256 userWeight_;
    for (uint256 i; i < _tokens.length; ++i) {
      userWeight_ +=
        (uint256(_userStakeInfo[user_][_tokens[i]].staked) * _tokenInfo[_tokens[i]].coefficient) /
        10**18;
    }
    return userWeight_;
  }

  function totalWeight() external view returns (uint256) {
    return _totalWeight;
  }

  function allowance(address, address) external pure returns (uint256) {
    return 0;
  }

  function transfer(address, uint256) external returns (bool) {
    _nonTransferable();
  }

  function transferFrom(
    address,
    address,
    uint256
  ) external returns (bool) {
    _nonTransferable();
  }

  function approve(address, uint256) external returns (bool) {
    _nonTransferable();
  }

  function _nonTransferable() internal virtual {
    revert("NON-TRANSFERABLE TOKEN");
  }

  function bond(address token_, uint256 amount_) external isStarted {
    _bond(token_, amount_, msg.sender);
  }

  function bondBatch(address[] memory tokens_, uint256[] memory amounts_) external isStarted {
    uint256 length_ = tokens_.length;
    address user_ = msg.sender;
    require(length_ == amounts_.length, "tokens length must be equal to amounts length");
    unchecked {
      for (uint256 i; i < length_; ++i) {
        _bond(tokens_[i], amounts_[i], user_);
      }
    }
  }

  function _bond(
    address token_,
    uint256 amount_,
    address user_
  ) internal nonReentrant {
    require(amount_ > 0, "cannot bond zero amount");
    IERC20(token_).safeTransferFrom(user_, address(this), amount_);
    TokenInfo storage tokenInfo_ = _tokenInfo[token_];
    require(tokenInfo_.index != 0, "Unsupported Token");
    StakeInfo storage userStakeInfo_ = _userStakeInfo[user_][token_];
    uint256 veTokenAmount = (uint256(amount_) * tokenInfo_.coefficient) / 10**18;
    tokenInfo_.totalStaked += amount_;
    userStakeInfo_.staked += amount_;
    _totalSupply += veTokenAmount;
    _totalWeight += veTokenAmount;
    emit Transfer(address(0), user_, veTokenAmount);
  }

  function requestUnbond(address token_, uint256 amount_) external isStarted {
    _requestUnbond(token_, amount_, msg.sender);
  }

  function requestUnbondBatch(address[] memory tokens_, uint256[] memory amounts_)
    external
    isStarted
  {
    uint256 length_ = tokens_.length;
    address user_ = msg.sender;
    require(length_ == amounts_.length, "tokens length must be equal to amounts length");
    unchecked {
      for (uint256 i; i < length_; ++i) {
        _requestUnbond(tokens_[i], amounts_[i], user_);
      }
    }
  }

  function _requestUnbond(
    address token_,
    uint256 amount_,
    address user_
  ) internal {
    StakeInfo storage userStakeInfo_ = _userStakeInfo[user_][token_];
    uint256 timestamp_ = uint256(block.timestamp);
    if (amount_ == type(uint256).max) {
      amount_ = userStakeInfo_.staked;
    }
    require(amount_ > 0, "Cannot request for zero amount");
    userStakeInfo_.staked -= amount_;
    userStakeInfo_.wantClaim += amount_;
    userStakeInfo_.requestTime = timestamp_;
    _totalWeight -= (uint256(amount_) * _tokenInfo[token_].coefficient) / 10**18;
    emit UnbondingRequest(token_, amount_, timestamp_);
  }

  function unbond(address token_) external {
    _unbond(token_, msg.sender);
  }

  function unbondBatch(address[] memory tokens_) external {
    uint256 length_ = tokens_.length;
    address user_ = msg.sender;
    unchecked {
      for (uint256 i; i < length_; ++i) {
        _unbond(tokens_[i], user_);
      }
    }
  }

  function _unbond(address token_, address user_) internal nonReentrant {
    StakeInfo storage userStakeInfo_ = _userStakeInfo[user_][token_];
    TokenInfo storage tokenInfo_ = _tokenInfo[token_];
    uint256 timestamp_ = uint256(block.timestamp);
    uint256 amount_ = userStakeInfo_.wantClaim;
    require(amount_ > 0, "Claimed amount should not be zero");
    require(userStakeInfo_.requestTime + WEEK <= timestamp_, "You should wait seven days");
    uint256 veTokenAmount = (uint256(amount_) * tokenInfo_.coefficient) / 10**18;
    tokenInfo_.totalStaked -= amount_;
    userStakeInfo_.wantClaim = 0;
    _totalSupply -= veTokenAmount;
    IERC20(token_).safeTransfer(user_, amount_);
    emit Transfer(user_, address(0), veTokenAmount);
  }

  function decreaseUnbondAmount(address token_, uint256 amount_) external {
    _decreaseUnbondAmount(token_, amount_, msg.sender);
  }

  function decreaseUnbondAmountBatch(address[] memory tokens_, uint256[] memory amounts_) external {
    uint256 length_ = tokens_.length;
    address user_ = msg.sender;
    require(length_ == amounts_.length, "tokens length must be equal to amounts length");
    unchecked {
      for (uint256 i; i < length_; ++i) {
        _decreaseUnbondAmount(tokens_[i], amounts_[i], user_);
      }
    }
  }

  function _decreaseUnbondAmount(
    address token_,
    uint256 amount_,
    address user_
  ) internal {
    StakeInfo storage userStakeInfo_ = _userStakeInfo[user_][token_];
    uint256 wantClaim_ = userStakeInfo_.wantClaim;
    if (amount_ == type(uint256).max) {
      amount_ = wantClaim_;
    }
    require(amount_ <= wantClaim_, "amount is more than wantClaim amount");
    userStakeInfo_.staked += amount_;
    _totalWeight += (uint256(amount_) * _tokenInfo[token_].coefficient) / 10**18;
    unchecked {
      uint256 remainingAmount = wantClaim_ - amount_;
      userStakeInfo_.wantClaim = remainingAmount;
      emit UnbondingRequest(token_, remainingAmount, userStakeInfo_.requestTime);
    }
  }

  function addToken(address newToken_, uint240 coefficient_) external onlyOwner {
    require(_tokenInfo[newToken_].index == 0, "Token already added");
    _tokens.push(newToken_);
    _tokenInfo[newToken_] = TokenInfo({
      coefficient: coefficient_,
      index: uint16(_tokens.length),
      totalStaked: 0
    });

    emit TokenAdded(newToken_, coefficient_);
  }

  function tokenInfo(address token_) public view returns (TokenInfo memory) {
    TokenInfo memory tokenInfo_ = _tokenInfo[token_];
    require(tokenInfo_.index != 0, "Unsupported token");
    return tokenInfo_;
  }

  function userStakeInfo(address user_, address token_) external view returns (StakeInfo memory) {
    return _userStakeInfo[user_][token_];
  }

  function getTokensLength() external view returns (uint256) {
    return _tokens.length;
  }

  function getTokenByIndex(uint256 index) external view returns (address) {
    return _tokens[index - 1];
  }

  function getTokenInfoByIndex(uint256 index) external view returns (TokenInfo memory) {
    return tokenInfo(_tokens[index - 1]);
  }
}