const { ethers } = require("hardhat");

//import { FTFSender_ADDRESS } from "../constants/addresses";

// const FTFSender_ADDRESS = "0x2d4dC4aDA01Bb17B1c705dd5a96E4a4CE9C9782C";

const FTFSender_ADDRESS = "0xd6aeda0ecc051aaabd0fd171ff04a5035ffa8c9c";

async function main() {
  // getting contracts
  const ftfSenderContract = await ethers.getContractAt(
    "IFarmTrustSender",
    FTFSender_ADDRESS
  );

  console.log("\n=========== WhitelistingChain ===========");

  await ftfSenderContract.whitelistChain("16015286601757825753"); // sepolia

  await ftfSenderContract.whitelistChain("14767482510784806043"); // Fuji

  await ftfSenderContract.whitelistChain("12532609583862916517"); // Mumbai

  await ftfSenderContract.whitelistChain("2664363617261496610"); // Optimism
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
