let { networkConfig, getNetworkIdFromName } = require('../../helper-hardhat-config')

task("bottlecap-announce","Announce available swap to BTLD market, first attempting to fill it without adding it") => {
// .setAction(async (taskArgs, hre)
  // const accounts = await hre.ethers.getSigners();
  // const networkId = network.name
  // const signer = accounts[hre.config.namedAccounts["tokenAccount"][networkId]];
  // const opsAccount = accounts[hre.config.namedAccounts["opsAccount"][networkId]];
  // const contractAddr = accounts[hre.config.namedAccount["shareAccount"]s[networkId]];
  //
  //
  // console.log("Announcing new BTLD bottle on network ", networkId)
  // const Bottlecap = await ethers.getContractFactory("Bottlecap")
  //
  //
  // // const signer = accounts[hre.config.namedAccounts[networkId]["owner"]];
  // const shareContract = new ethers.Contract(contractAddr, Bottlecap.interface, signer)
  // let result = await shareContract.announce(opsAccount,3);
  //
  // console.log('BTLD Minted Market Response is');
  // console.log(result);
  //
  // if (result == 0 && ['hardhat', 'localhost', 'ganache'].indexOf(network.name) == 0) {
  //     console.log("You'll either need to wait another minute, or fix something!")
  // }
  // if (['hardhat', 'localhost', 'ganache'].indexOf(network.name) >= 0) {
  //     console.log("You'll have to manually update the value since you're on a local chain!")
  // }
});

module.exports = {}
