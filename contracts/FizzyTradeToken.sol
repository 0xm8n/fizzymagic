// SPDX-License-Identifier: MIT
// Fizzy Trade Token

pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "./standards/ERC20.sol";
import "./utils/ExecutorAccess.sol";

contract FizzyTradeToken is ERC20, ExecutorAccess {

    constructor(string memory name, string memory symbol, address exceutor) ERC20(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(EXECUTOR_ROLE, exceutor);
    }

    function mint(address to, uint256 amount) public onlyExecutor{
        _mint(to, amount);
    }

    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, deducting from the caller"s
     * allowance.
     *
     * See {ERC20-_burn} and {ERC20-allowance}.
     *
     * Requirements:
     *
     * - the caller must have allowance for ``accounts``"s tokens of at least
     * `amount`.
     */
    function burnFrom(address account, uint256 amount) public {
        uint256 currentAllowance = allowance(account, _msgSender());
        require(currentAllowance >= amount, "ERC20: burn amount exceeds allowance");
        unchecked {
            _approve(account, _msgSender(), currentAllowance - amount);
        }
        _burn(account, amount);
    }

}
