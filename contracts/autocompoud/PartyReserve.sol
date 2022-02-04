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

contract PartyReserve is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable rewardToken;
    address public party;

    uint256 public balances;

    event Deposit(address from, uint256 amount);

    constructor(IERC20 _rewardToken) {
        rewardToken = _rewardToken;
    }

    function setParty(address _party) external onlyOwner {
        require(party == address(0), "?");
        require(IReserveWithdrawer(_party).reserve() == address(this), "invalid party");

        party = _party;
    }

    function withdraw(address to, uint256 amount) external returns (uint256) {
        require(msg.sender == party, "!withdrawer");

        return _safeTransfer(to, amount);
    }

    function deposit(uint256 amount) external {
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        balances += amount;
        emit Deposit(msg.sender, amount);
    }

    function _safeTransfer(address to, uint256 amount) private returns (uint256) {
        amount = Math.min(amount, balances);
        if (amount > 0) {
            balances -= amount;
            rewardToken.safeTransfer(to, amount);
        }

        return amount;
    }
}
