task("bottlecap-send","Deploys BTLD");
.addOptionalParam("minter")
.addOptionalParam("reserve") => {
// .setAction(async (taskArgs, hre)
  // const accounts = await hre.ethers.getSigners();
  // const networkId = network.name;
  // const signer = accounts[hre.config.namedAccounts["owner"][networkId]];
  //
  // // const opsAccount = accounts[hre.config.namedAccounts[networkId]["opsAccount"]];
  //
  // const tokensAddr = "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0";//accounts[hre.config.namedAccounts["tokenAccount"][networkId]];
  // const shareAddr = "0xdc64a140aa3e981100a9beca4e685f962f0cf6c9";//accounts[hre.config.namedAccounts["shareAccount"][networkId]];
  //
  // const Bottlecap = await ethers.getContractFactory("Bottlecap",signer);
  // Bottlecap.attach(shareAddr);
  //
  // console.log("Deploying BTLD");
  // const instance = await upgrades.deployProxy(Bottlecap, [1000000000000]);
  // // const instance = await upgrades.deployProxy(FractionalFiat, [taskArgs.minter]);
  // await instance.deployed();
  // console.log("BTLD deployed to: ", instance.address);
  // return instance.address;
});

module.exports = {}
