// SPDX-License-Identifier: MIT
// Kswzy Money Token

pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FizzyMoneyToken is ERC20, Ownable {
    constructor(address exceutor) ERC20("Fizzy Money Token", "FZM") {
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }
}
