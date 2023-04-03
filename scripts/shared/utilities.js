const { ethers } = require('hardhat');
const { BigNumber } = ethers;
const ZERO_ADDRESS = ethers.constants.AddressZero;

// Defaults to e18 using amount * 10^18
function getBigNumber(amount, decimals = 18) {
  return BigNumber.from(amount).mul(BigNumber.from(10).pow(decimals));
}

async function advanceBlock() {
  return ethers.provider.send('evm_mine', []);
}

async function advanceBlockTo(blockNumber) {
  for (let i = await ethers.provider.getBlockNumber(); i < blockNumber; i++) {
    await advanceBlock();
  }
}

module.exports = {
  ZERO_ADDRESS,
  getBigNumber,
  advanceBlock,
  advanceBlockTo
};
