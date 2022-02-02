// SPDX-License-Identifier: MIT
// Fizzy Magic

pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Fizzy Magic

contract FizzyMagicToken is Ownable, ERC20 {
    uint256 public _maxSupply;

    constructor(uint256 cap) ERC20("Fizzy Magic Token", "FIZ") {
        require(cap > 0, "ERC20: cap is 0");
        _maxSupply = cap;
    }

    function maxSupply() public view virtual returns (uint256) {
        return _maxSupply;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        require(ERC20.totalSupply() + amount <= maxSupply(), "ERC20: cap exceeded");
        _mint(to, amount);
    }

    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }
}
