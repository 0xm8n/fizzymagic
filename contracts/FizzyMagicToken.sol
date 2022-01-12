// SPDX-License-Identifier: MIT

// Fizzy Magic
// OpenZeppelin

pragma solidity 0.8.11;
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Fizzy Magic
/// @dev This contract allows contract calls to any contract (except BentoBox)
/// from arbitrary callers thus, don't trust calls from this contract in any circumstances.

abstract contract FizzyMagic is ERC20Capped, Ownable {

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to,amount);
    }
}
