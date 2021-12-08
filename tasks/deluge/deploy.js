task("deluge-deploy","Deploys XFD");
.addOptionalParam("minter")
.addOptionalParam("reserve")
.setAction(async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();
  const networkId = network.name;
  const signer = accounts[hre.config.namedAccounts["owner"][networkId]];

  // const opsAccount = accounts[hre.config.namedAccounts[networkId]["opsAccount"]];

  const tokensAddr = "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0";//accounts[hre.config.namedAccounts["tokenAccount"][networkId]];
  const shareAddr = "0xdc64a140aa3e981100a9beca4e685f962f0cf6c9";//accounts[hre.config.namedAccounts["shareAccount"][networkId]];

  const FractionalFiat = await ethers.getContractFactory("FractionalDeluge",signer);
  FractionalFiat.attach(shareAddr);

  console.log("Deploying XFD");
  const instance = await upgrades.deployProxy(FractionalFiat, [tokensAddr,shareAddr]);
  // const instance = await upgrades.deployProxy(FractionalFiat, [taskArgs.minter]);
  await instance.deployed();
  console.log("XFD deployed to: ", instance.address);
  return instance.address;
});

module.exports = {}
