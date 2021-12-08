require('hardhat-deploy');
require('hardhat-deploy-ethers');
require('hardhat-contract-sizer');

 require("./tasks/bottlecap");

module.exports = {
  solidity: {
    compilers: [
        {
            version: "0.8.4"
        },
        {
            version: "0.8.0"
        },
        {
            version: "0.7.3"
        },
        {
            version: "0.6.6"
        },
        {
            version: "0.4.24"
        }
    ]
},
};
