// Defining bytecode and abi from original contract on mainnet to ensure bytecode matches and it produces the same pair code hash
const { getBigNumber } = require('../scripts/shared/utilities.js');

module.exports = async function ({ ethers, getNamedAccounts, deployments, getChainId }) {
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()

  const SB_PER_BLOCK = getBigNumber(5, 14); // 0.0005 SB per block
  const rewardTimeStamp = 1646080259; // ~~((new Date()).getTime() / 1000 + 500) ; // 2022-02-10 01:43:08 PM GMT

  await deploy('SBMasterChef', {
    from: deployer,
    log: true,
    args: [SB_PER_BLOCK, rewardTimeStamp],
    deterministicDeployment: false,
  })
}

module.exports.tags = ["SBMasterChef", "SB"];
