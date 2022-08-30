import { ethers } from "hardhat";

const main = async () => {
  const Farming = await ethers.getContractFactory("Farming");
  const farming = await Farming.deploy();
  await farming.deployed();
  console.log(farming.address);
};

main();
