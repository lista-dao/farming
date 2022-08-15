import { BigNumber } from "ethers";
import fs from "fs";
import hre, { ethers, network, upgrades } from "hardhat";
import { Farming, IncentiveVoting, TokenBonding } from "../typechain-types";
import { hoursToSeconds, getNextTimestampDivisibleBy } from "./helpers/utils";

const HAY = "0x7adC9A28Fab850586dB99E7234EA2Eb7014950fA";

const verifyContract = async (contractAddress: string, constructorArguments: Array<any>) => {
  const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

  try {
    const tx = await hre.run("verify:verify", {
      address: contractAddress,
      constructorArguments,
    });
    console.log(tx);

    await sleep(16000);
  } catch (error) {
    console.log("error is ->");
    console.log(error);
    console.log("cannot verify contract", contractAddress);
    await sleep(16000);
  }
  console.log("contract", contractAddress, "verified successfully");
};

const ten = BigNumber.from(10);
const tenPow18 = ten.pow(18);
const fakeWeek = hoursToSeconds(BigNumber.from(1)); // 1 hour

const main = async () => {
  const FakeToken = await ethers.getContractFactory("FakeERC20");
  const StrategyMock = await ethers.getContractFactory("StrategyMock");
  const TokenBonding = await ethers.getContractFactory("TokenBonding");
  const IncentiveVoting = await ethers.getContractFactory("IncentiveVoting");
  const Farming = await ethers.getContractFactory("Farming");

  const startTime = await getNextTimestampDivisibleBy(fakeWeek.toNumber());

  const fakeHelio = await FakeToken.deploy("FakeHelio", "FakeHelio");
  const fakeHelioLP = await FakeToken.deploy("FakeHelioLP", "FakeHelioLP");
  const fakeHay = await FakeToken.deploy("FakeHay", "FakeHay");
  await fakeHelio.deployed();
  await fakeHelioLP.deployed();
  await fakeHay.deployed();
  const helioCoefficient = tenPow18.mul(1);
  const helioLpCoefficient = tenPow18.mul(2);

  const tokens = [fakeHelio.address, fakeHelioLP.address];
  const coefficients = [helioCoefficient.toString(), helioLpCoefficient.toString()];
  const tokenBonding = (await upgrades.deployProxy(TokenBonding, [
    startTime,
    tokens,
    coefficients,
  ])) as TokenBonding;
  await tokenBonding.deployed();

  const incentiveVoting = (await upgrades.deployProxy(IncentiveVoting, [
    tokenBonding.address,
  ])) as IncentiveVoting;
  await incentiveVoting.deployed();
  const farming = (await upgrades.deployProxy(Farming, [HAY, incentiveVoting.address])) as Farming;
  await farming.deployed();
  const fakeHayStrategy = await StrategyMock.deploy(fakeHay.address, farming.address);
  await fakeHayStrategy.deployed();
  const hayStrategy = await StrategyMock.deploy(HAY, farming.address);
  await hayStrategy.deployed();

  const addresses = {
    fakeHelio: fakeHelio.address,
    fakeHelioLP: fakeHelioLP.address,
    fakeHay: fakeHay.address,
    hay: HAY,
    tokenBonding: tokenBonding.address,
    incentiveVoting: incentiveVoting.address,
    farming: farming.address,
    fakeHayStrategy: fakeHayStrategy.address,
    hayStrategy: hayStrategy.address,
  };
  const jsonAddresses = JSON.stringify(addresses);
  fs.writeFileSync(`./addresses/${network.name}Addresses.json`, jsonAddresses);
  console.log("Addresses saved!");

  // set Farming
  await incentiveVoting.setFarming(
    farming.address,
    [fakeHay.address, HAY],
    [fakeHayStrategy.address, hayStrategy.address]
  );
  console.log("farming setted");

  await verifyContract(fakeHelio.address, ["FakeHelio", "FakeHelio"]);
  await verifyContract(fakeHelioLP.address, ["FakeHelioLP", "FakeHelioLP"]);
  await verifyContract(fakeHay.address, ["FakeHay", "FakeHay"]);
  await verifyContract(tokenBonding.address, [startTime.toString(), tokens, coefficients]);
  await verifyContract(incentiveVoting.address, [tokenBonding.address]);
  await verifyContract(farming.address, [HAY, incentiveVoting.address]);
  await verifyContract(fakeHayStrategy.address, [fakeHay.address, farming.address]);
  await verifyContract(hayStrategy.address, [HAY, farming.address]);
};

main()
  .then(() => {
    console.log("Success");
  })
  .catch((err) => {
    console.log(err);
  });
