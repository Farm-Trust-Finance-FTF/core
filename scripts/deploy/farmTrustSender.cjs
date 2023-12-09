const { ethers } = require("hardhat");
const { verify } = require("../../utils/verify.cjs");
const { network } = require("hardhat");

// const ROUTER_ADDRESS = "0x554472a2720e5e7d5d3c817529aba05eed5f82d8";
// const LINK_ADDRESS = "0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846";

// sepolia
const ROUTER_ADDRESS = "0xd0daae2231e9cb96b94c8512223533293c3693bf";
const LINK_ADDRESS = "0x779877A7B0D9E8603169DdbD7836e478b4624789";

async function main() {
  const farmTrustSenderContract = await ethers.deployContract(
    "FarmTrustSender",
    [ROUTER_ADDRESS, LINK_ADDRESS]
  );

  console.log("========= Deploying FarmTrustSender Contract ================");

  await farmTrustSenderContract.deployTransaction.wait();

  console.log(
    `FarmTrustSender Contract deployed to: ${farmTrustSenderContract.address}`
  );

  if (network.config.chainId === 11155111 && process.env.ETHERSCAN_API_KEY) {
    console.log("Waiting for block confirmations...");

    await farmTrustSenderContract.deployTransaction.wait(6);
    await verify(farmTrustSenderContract.address, [
      ROUTER_ADDRESS,
      LINK_ADDRESS,
    ]);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

// 0x2d4dC4aDA01Bb17B1c705dd5a96E4a4CE9C9782C

// https://testnet.snowtrace.io/address/0x2d4dC4aDA01Bb17B1c705dd5a96E4a4CE9C9782C#code

// sepolia

// 0xd6aeDa0EcC051aAABd0fD171FF04a5035fFa8C9c

// https://sepolia.etherscan.io/address/0xd6aeDa0EcC051aAABd0fD171FF04a5035fFa8C9c#code
