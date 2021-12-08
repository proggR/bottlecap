// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ShitGold is ERC20 {
    constructor(uint256 initialSupply) public ERC20("ShitGold", "SGLD") {
        _mint(msg.sender, initialSupply);
    }
}

contract ShitSilver is ERC20 {
    constructor(uint256 initialSupply) public ERC20("ShitSilver", "SSLV") {
        _mint(msg.sender, initialSupply);
    }
}

contract ShitBronze is ERC20 {
    constructor(uint256 initialSupply) public ERC20("ShitBronze", "SBRZ") {
        _mint(msg.sender, initialSupply);
    }
}

contract ShitShit is ERC20 {
    constructor(uint256 initialSupply) public ERC20("ShitShit", "SSHIT") {
        _mint(msg.sender, initialSupply);
    }
}
