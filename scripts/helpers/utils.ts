import { BigNumber } from "ethers";

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
  const blockTimestamp = Math.floor(Date.now() / 1000);
  const numCount = BigNumber.from(blockTimestamp).div(num);
  return numCount.add(1).mul(num);
};

export default {
  daysToSeconds,
  hoursToSeconds,
  minutesToSeconds,
  getNextTimestampDivisibleBy,
};
