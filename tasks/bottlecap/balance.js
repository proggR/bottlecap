let { networkConfig, getNetworkIdFromName } = require('../../helper-hardhat-config')

task("bottlecap-balance", "Prints an account's balance")
.addOptionalParam("address", "The account's address address")
.setAction(async taskArgs => {
  const provider = new ethers.providers.JsonRpcProvider();
  const accounts = await ethers.getSigners()
  const networkId = network.name;
  // const contractAddr = accounts[hre.config.namedAccounts["tokenAccount"][networkId]];

  console.log("Reading balance for",taskArgs.name," from Bottlecap contract 0x5fbdb2315678afecb367f032d93f642f64180aa3 on network ", networkId)
  const Bottlecap = await ethers.getContractFactory("Bottlecap")

  //Get signer information
  const signer = accounts[0];

  //Create connection to API Consumer Contract and call the createRequestTo function
  // const tokenContract = new ethers.Contract(contractAddr.address, Bottlecap.interface, signer)
  const tokenContract = new ethers.Contract("0x5fbdb2315678afecb367f032d93f642f64180aa3", Bottlecap.interface, signer)
  let result = BigInt(await tokenContract.balanceOf(taskArgs.address)).toString();
  console.log('Token Balance is: ', result)
  if (result == 0 && ['hardhat', 'localhost', 'ganache'].indexOf(network.name) == 0) {
      console.log("You'll either need to wait another minute, or fix something!")
  }
  if (['hardhat', 'localhost', 'ganache'].indexOf(network.name) >= 0) {
      console.log("You'll have to manually update the value since you're on a local chain!")
  }

});

module.exports = {};
