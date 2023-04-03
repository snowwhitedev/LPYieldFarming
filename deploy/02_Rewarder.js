// Defining bytecode and abi from original contract on mainnet to ensure bytecode matches and it produces the same pair code hash
const { getBigNumber } = require('../scripts/shared/utilities.js');

module.exports = async function ({ ethers, getNamedAccounts, deployments, getChainId }) {
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()

  const SB_ADDRESS = '0x40f906e19b14100d5247686e08053c4873c66192' // SB on BSC mainnet  // '0xaba66801a23458f6ff888c03e0453b747c1fa61b'; // Mock SB on testnet
  const SB_MASTER_CHEF = await deployments.get("SBMasterChef");

  await deploy('Rewarder', {
    from: deployer,
    log: true,
    args: [SB_ADDRESS, SB_MASTER_CHEF.address],
    deterministicDeployment: false,
  })
}

module.exports.tags = ["Rewarder", "SB"];
module.exports.dependencies = ["SBMasterChef"]
