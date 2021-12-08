let { networkConfig, getNetworkIdFromName } = require('../../helper-hardhat-config')

task("deluge-announce","Announce available swap to XFD market, first attempting to fill it without adding it")
.setAction(async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();
  const networkId = network.name
  const signer = accounts[hre.config.namedAccounts["tokenAccount"][networkId]];
  const opsAccount = accounts[hre.config.namedAccounts["opsAccount"][networkId]];
  const contractAddr = accounts[hre.config.namedAccount["shareAccount"]s[networkId]];


  console.log("Announcing new XFD bottle on network ", networkId)
  const FractionalFiat = await ethers.getContractFactory("FractionalFiat")


  // const signer = accounts[hre.config.namedAccounts[networkId]["owner"]];
  const shareContract = new ethers.Contract(contractAddr, FractionalFiat.interface, signer)
  let result = await shareContract.announce(opsAccount,3);

  console.log('XFD Minted Market Response is');
  console.log(result);

  if (result == 0 && ['hardhat', 'localhost', 'ganache'].indexOf(network.name) == 0) {
      console.log("You'll either need to wait another minute, or fix something!")
  }
  if (['hardhat', 'localhost', 'ganache'].indexOf(network.name) >= 0) {
      console.log("You'll have to manually update the value since you're on a local chain!")
  }
});

module.exports = {}
