let { networkConfig} = require('../helper-hardhat-config')

module.exports = async ({
  getNamedAccounts,
  deployments
}) => {
  const { deploy, log, get } = deployments
  // const { deployer } = await getNamedAccounts()
  // const chainId = await getChainId()
  //set log level to ignore non errors
  ethers.utils.Logger.setLogLevel(ethers.utils.Logger.levels.ERROR)

  // addresses: initialOfferingAddress, marketRewardAddress, airdropAddress, personalAddress
  //,"0x70997970c51812dc3a010c7d01b50e0d17dc79c8","0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc","0x90f79bf6eb2c4f870365e785982e1f101e93b906","0x15d34aaf54267db7d7c367839aaf71a00a2c6a65"
  const basicContract = await deploy('Bottlecap', {
    from: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
    args: [1000000000000],
    log: true
  })

}
module.exports.tags = ['all', 'main']
