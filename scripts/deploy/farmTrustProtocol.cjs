const { ethers } = require("hardhat");
const { verify } = require("../../utils/verify.cjs");
const { network } = require("hardhat");

// Fuji
// const ROUTER_ADDRESS = "0x554472a2720e5e7d5d3c817529aba05eed5f82d8";
// const LINK_ADDRESS = "0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846";

// sepolia
const ROUTER_ADDRESS = "0xd0daae2231e9cb96b94c8512223533293c3693bf";
const LINK_ADDRESS = "0x779877A7B0D9E8603169DdbD7836e478b4624789";

async function main() {
  const farmTrustProtocolContract = await hre.ethers.deployContract(
    "FarmTrustProtocol",
    [ROUTER_ADDRESS, LINK_ADDRESS]
  );

  console.log(
    "========= Deploying FarmTrustProtocol Contract ================"
  );

  await farmTrustProtocolContract.deployTransaction.wait();

  console.log(
    `FarmTrustSender Contract deployed to: ${farmTrustProtocolContract.address}`
  );

  if (network.config.chainId === 11155111 && process.env.ETHERSCAN_API_KEY) {
    console.log("Waiting for block confirmations...");

    await farmTrustProtocolContract.deployTransaction.wait(6);
    await verify(farmTrustProtocolContract.address, [
      ROUTER_ADDRESS,
      LINK_ADDRESS,
    ]);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

// 0x0171A98115661783B8E46c1200237e6B202362C7

// https://testnet.snowtrace.io/address/0x0171A98115661783B8E46c1200237e6B202362C7#code

// sepolia

//  0xCa4D981fC61Cd389326aD1529E7C93A27B31987e

// https://sepolia.etherscan.io/address/0xCa4D981fC61Cd389326aD1529E7C93A27B31987e#code
