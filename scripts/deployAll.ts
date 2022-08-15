import { BigNumber } from "ethers";
import fs from "fs";
import hre, { ethers, network, upgrades } from "hardhat";
import { hoursToSeconds, getNextTimestampDivisibleBy } from "./helpers/utils";

const ten = BigNumber.from(10);
const tenPow18 = ten.pow(18);
const fakeWeek = hoursToSeconds(BigNumber.from(1)); // 1 hour

const HAY = "";
const HELIO = "";
const MIN_EARN_AMT = "";
const MASTERCHEF = "";
const WANT = "";
const CAKE = "";
const TOKEN0 = "";
const TOKEN1 = "";
const ROUTER = "";
const EARNED_TO_TOKEN0_PATH: string[] = [];
const EARNED_TO_TOKEN1_PATH: string[] = [];

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

const main = async () => {
  const FarmingFactory = await ethers.getContractFactory("Farming");
  const TokenBondingFactory = await ethers.getContractFactory("TokenBonding");
  const IncentiveVotingFactory = await ethers.getContractFactory("IncentiveVoting");
  const PancakeStrategyFactory = await ethers.getContractFactory("PancakeStrategy");
  const PancakeProxyForDepositFactory = await ethers.getContractFactory("PancakeProxyForDeposit");

  const startTime = await getNextTimestampDivisibleBy(fakeWeek.toNumber());

  const helioCoefficient = tenPow18.mul(1);

  const tokens = [HELIO];
  const coefficients = [helioCoefficient.toString()];
  const tokenBonding = await upgrades.deployProxy(TokenBondingFactory, [
    startTime,
    tokens,
    coefficients,
  ]);
  await tokenBonding.deployed();
  const tokenBondingImpl = await tokenBonding.erc1967.getImplementation();

  const incentiveVoting = await upgrades.deployProxy(IncentiveVotingFactory, [
    tokenBonding.address,
  ]);
  await incentiveVoting.deployed();
  const incentiveVotingImpl = await incentiveVoting.erc1967.getImplementation();

  const farming = await upgrades.deployProxy(FarmingFactory, [HAY, incentiveVoting.address]);
  await farming.deployed();
  const farmingImpl = await farming.erc1967.getImplementation();

  const pancakeStrategy = await upgrades.deployProxy(PancakeStrategyFactory, [
    MIN_EARN_AMT,
    false,
    [MASTERCHEF, WANT, CAKE, TOKEN0, TOKEN1, ROUTER, farming.address],
    EARNED_TO_TOKEN0_PATH,
    EARNED_TO_TOKEN1_PATH,
  ]);
  await pancakeStrategy.deployed();
  const pancakeStrategyImpl = await pancakeStrategy.erc1967.getImplementation();

  const pancakeProxyForDeposit = await upgrades.deployProxy(PancakeProxyForDepositFactory, [
    farming.address,
    ROUTER,
  ]);
  await pancakeProxyForDeposit.deployed();
  const pancakeProxyForDepositImpl = await pancakeProxyForDeposit.erc1967.getImplementation();

  const addresses = {
    hay: HAY,
    helio: HELIO,
    tokenBonding: tokenBonding.address,
    tokenBondingImplementation: tokenBondingImpl,
    incentiveVoting: incentiveVoting.address,
    incentiveVotingImplementation: incentiveVotingImpl,
    farming: farming.address,
    farmingImplementation: farmingImpl,
    pancakeProxyForDeposit: pancakeProxyForDeposit.address,
    pancakeProxyForDepositImplementation: pancakeProxyForDepositImpl,
    pancakeStrategy: pancakeStrategy.address,
    pancakeStrategyImplementation: pancakeStrategyImpl,
  };
  const jsonAddresses = JSON.stringify(addresses);
  fs.writeFileSync(`./addresses/${network.name}Addresses.json`, jsonAddresses);
  console.log("Addresses saved!");

  // set Farming
  await incentiveVoting.setFarming(farming.address, [WANT], [pancakeStrategy.address]);
  console.log("farming setted");
  // set supported token to proxy for farming
  await pancakeProxyForDeposit.addSupportedTokens(TOKEN0, TOKEN1, 0);
  console.log("proxy for farming config competed");

  await verifyContract(farmingImpl, []);
  await verifyContract(tokenBondingImpl, []);
  await verifyContract(incentiveVotingImpl, []);
  await verifyContract(pancakeStrategyImpl, []);
  await verifyContract(pancakeProxyForDepositImpl, []);
};

main()
  .then(() => {
    console.log("Success");
  })
  .catch((err) => {
    console.log(err);
  });
