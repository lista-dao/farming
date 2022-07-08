// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./interfaces/IRatioToken.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract NativeOracle {
  AggregatorV3Interface public priceFeed;
  IRatioToken public token;

  constructor(address aggregatorAddress, address _token) {
    priceFeed = AggregatorV3Interface(aggregatorAddress);
    token = IRatioToken(_token);
  }

  /**
   * Returns the latest price
   */
  function peek() public view returns (bytes32, bool) {
    (, int256 price, , , ) = priceFeed.latestRoundData();
    if (price < 0) {
      return (0, false);
    }
    uint256 ratio = token.ratio();
    if (ratio == 0) {
      return (0, false);
    }
    return (bytes32((uint256(price) * (10**28)) / ratio), true);
  }
}
