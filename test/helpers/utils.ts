import { BigNumber } from "ethers";
import { ethers, network } from "hardhat";

export const advanceTime = async (seconds: number) => {
  await network.provider.send("evm_increaseTime", [seconds]);
  await network.provider.send("evm_mine");
};

export const advanceBlock = async (blockCount: number) => {
  for (let i = 0; i < blockCount; i++) {
    await network.provider.send("evm_mine");
  }
};

export const advanceBlockAndTime = async (blockCount: number, seconds: number) => {
  const secondPerBlock = Math.floor(seconds / blockCount);
  for (let i = 0; i < blockCount; i++) {
    await advanceTime(secondPerBlock);
  }
};

export const setTimestamp = async (seconds: number) => {
  await network.provider.send("evm_setNextBlockTimestamp", [seconds]);
  await network.provider.send("evm_mine");
};

export const getTimestamp = async (): Promise<number> => {
  const blockNumber = await ethers.provider.getBlockNumber();
  const block = await ethers.provider.getBlock(blockNumber);
  return block.timestamp;
};

export const daysToSeconds = (days: BigNumber): BigNumber => {
  return hoursToSeconds(days.mul(24));
};

export const hoursToSeconds = (hours: BigNumber): BigNumber => {
  return minutesToSeconds(hours.mul(60));
};

export const minutesToSeconds = (minutes: BigNumber): BigNumber => {
  return minutes.mul(60);
};

export const getNextTimestampDivisibleBy = async (num: number): Promise<BigNumber> => {
  const blockTimestamp = await getTimestamp();
  const numCount = BigNumber.from(blockTimestamp).div(num);
  return numCount.add(1).mul(num);
};

export default {
  advanceTime,
  advanceBlock,
  advanceBlockAndTime,
  setTimestamp,
  getTimestamp,
  daysToSeconds,
  hoursToSeconds,
  minutesToSeconds,
  getNextTimestampDivisibleBy,
};
