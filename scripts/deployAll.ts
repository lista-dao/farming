import { BigNumber } from "ethers";
import fs from "fs";
import hre, { ethers, network, upgrades } from "hardhat";
import { getNextTimestampDivisibleBy, daysToSeconds, verifyContract } from "../helpers/utils";

const ten = BigNumber.from(10);
const tenPow18 = ten.pow(18);
const week = daysToSeconds(BigNumber.from(7)); // 7 days

const HAY = "";
const MIN_EARN_AMT = "";
const MASTERCHEF = "";
const WANT = "";
const CAKE = "";
const TOKEN0 = "";
const TOKEN1 = "";
const ROUTER = "";
const EARNED_TO_TOKEN0_PATH: string[] = [];
const EARNED_TO_TOKEN1_PATH: string[] = [];

const main = async () => {
  const FarmingFactory = await ethers.getContractFactory("Farming");
  const IncentiveVotingFactory = await ethers.getContractFactory("IncentiveVoting");
  const PancakeStrategyFactory = await ethers.getContractFactory("PancakeStrategy");
  const PancakeProxyForDepositFactory = await ethers.getContractFactory("PancakeProxyForDeposit");

  const startTime = await getNextTimestampDivisibleBy(week.toNumber());

  const incentiveVoting = await upgrades.deployProxy(IncentiveVotingFactory, [startTime]);
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
