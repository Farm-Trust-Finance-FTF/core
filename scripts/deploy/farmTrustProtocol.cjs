const { ethers } = require("hardhat");
const { verify } = require("../../utils/verify.cjs");
const { network } = require("hardhat");

const ROUTER_ADDRESS = "0x554472a2720e5e7d5d3c817529aba05eed5f82d8";
const LINK_ADDRESS = "0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846";

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

  if (network.config.chainId === 43113 && process.env.SNOWTRACE_API_KEY) {
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
