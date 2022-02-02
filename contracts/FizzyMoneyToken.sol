// SPDX-License-Identifier: MIT
// Fizzy Money Token

pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./utils/ExecutorAccess.sol";

contract FizzyMoneyToken is ERC20, ExecutorAccess {
    constructor(address exceutor) ERC20("Fizzy Money Token", "FZM") {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(EXECUTOR_ROLE, exceutor);
    }

    function mint(address to, uint256 amount) public onlyExecutor {
        _mint(to, amount);
    }

    // function mintToBentoBox(address clone, uint256 amount, BentoBox bentobox) public onlyExecutor {
    //     mint(address(bentoBox), amount);
    //     bentoBox.deposit(IERC20(address(this)), address(bentoBox), clone, amount, 0);
    // }

    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }
}
