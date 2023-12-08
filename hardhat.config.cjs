require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const FORK_FUJI = true;
const FORK_MAINNET = false;
let forkingData = undefined;

if (FORK_MAINNET) {
  forkingData = {
    url: "https://api.avax.network/ext/bc/C/rpcc",
  };
}
if (FORK_FUJI) {
  forkingData = {
    url: "https://avalanche-fuji-c-chain.publicnode.com",
  };
}

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.19",
  networks: {
    fuji: {
      url: "https://avalanche-fuji-c-chain.publicnode.com",
      chainId: 43113,
      accounts: [process.env.PRIVATE_KEY],
    },
    mainnet: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      gasPrice: 225000000000,
      chainId: 43114,
      accounts: [process.env.PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: process.env.SNOWTRACE_API_KEY,
  },
};

// npx hardhat verify <contract address> <arguments> --network <network>

// $ npx hardhat run scripts/deploy.js --network fuji

// npx hardhat verify 0x6bA59B015c2c9Aed6431E36e0e12Db89daBC18E9  "0x554472a2720e5e7d5d3c817529aba05eed5f82d8, 0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846" --network fuji
