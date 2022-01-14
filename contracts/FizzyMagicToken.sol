// SPDX-License-Identifier: MIT
// Fizzy Magic

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Fizzy Magic
/// @dev This contract allows contract calls to any contract (except BentoBox)
/// from arbitrary callers thus, don't trust calls from this contract in any circumstances.

contract FizzyMagicToken is Context, ERC20Burnable, Ownable {

    uint256 private immutable _maxSupply;

    constructor(string memory name, string memory symbol, uint256 cap) ERC20(name, symbol) {
        require(cap > 0, "ERC20: cap is 0");
        _maxSupply = cap;
    }

    function maxSupply() public view virtual returns (uint256) {
        return _maxSupply;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        require(ERC20.totalSupply() + amount <= maxSupply(), "ERC20: cap exceeded");
        _mint(to,amount);
    }
}
