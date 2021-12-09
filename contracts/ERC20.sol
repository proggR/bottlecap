// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FoolsGold is ERC20 {
    constructor(uint256 initialSupply) public ERC20("FoolsGold", "FGLD") {
        _mint(msg.sender, initialSupply);
    }
}

contract FoolsSilver is ERC20 {
    constructor(uint256 initialSupply) public ERC20("FoolsSilver", "FSLV") {
        _mint(msg.sender, initialSupply);
    }
}

contract FoolsBronze is ERC20 {
    constructor(uint256 initialSupply) public ERC20("FoolsBronze", "FBRZ") {
        _mint(msg.sender, initialSupply);
    }
}

contract Foobar is ERC20 {
    constructor(uint256 initialSupply) public ERC20("Foobar", "FOO") {
        _mint(msg.sender, initialSupply);
    }
}
