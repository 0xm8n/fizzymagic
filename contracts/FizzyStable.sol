// SPDX-License-Identifier: MIT

// Fizzy Absolute Stable
// OpenZeppelin

pragma solidity >=0.8.6;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Fizzy Stable
/// @dev This contract allows contract calls to any contract (except BentoBox)
/// from arbitrary callers thus, don't trust calls from this contract in any circumstances.
abstract contract FizzyStable is ERC20, Ownable {

    struct Minting {
        uint128 time;
        uint128 amount;
    }

    Minting public lastMint;
    uint256 private constant MINTING_PERIOD = 24 hours;
    uint256 private constant MINTING_INCREASE = 15000;
    uint256 private constant MINTING_PRECISION = 1e5;

    function mint(address to, uint256 amount) public onlyOwner {
        // Limits the amount minted per period to a convergence function, with the period duration restarting on every mint
        uint256 totalMintedAmount = uint256(lastMint.time < block.timestamp - MINTING_PERIOD ? 0 : lastMint.amount) + amount;
        require(totalSupply() == 0 || totalSupply() * MINTING_INCREASE / MINTING_PRECISION >= totalMintedAmount);

        lastMint.time = uint128(block.timestamp);
        lastMint.amount = uint128(totalMintedAmount);

        _mint(to,amount);
    }

    // function mintToBentoBox(address clone, uint256 amount, IBentoBoxV1 bentoBox) public onlyOwner {
    //     mint(address(bentoBox), amount);
    //     bentoBox.deposit(IERC20(address(this)), address(bentoBox), clone, amount, 0);
    // }

    function burn(uint256 amount) public onlyOwner {
        _burn(_msgSender(), amount);
    }

}
