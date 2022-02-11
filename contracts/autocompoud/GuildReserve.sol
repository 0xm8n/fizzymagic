// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../utils/Math.sol";

interface IReserveWithdrawer {
    function reserve() external returns (address);
}

contract GuildReserve is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable questReward;
    address public guild;

    uint256 public balances;

    event Deposit(address from, uint256 amount);

    constructor(IERC20 _questReward) {
        questReward = _questReward;
    }

    function setGuild(address _guild) external onlyOwner {
        require(guild == address(0), "?");
        require(IReserveWithdrawer(_guild).reserve() == address(this), "invalid guild");

        guild = _guild;
    }

    function withdraw(address to, uint256 amount) external returns (uint256) {
        require(msg.sender == guild, "!withdrawer");

        return _safeTransfer(to, amount);
    }

    function deposit(uint256 amount) external {
        questReward.safeTransferFrom(msg.sender, address(this), amount);
        balances += amount;
        emit Deposit(msg.sender, amount);
    }

    function _safeTransfer(address to, uint256 amount) private returns (uint256) {
        amount = Math.min(amount, balances);
        if (amount > 0) {
            balances -= amount;
            questReward.safeTransfer(to, amount);
        }

        return amount;
    }
}
