// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IQuestGuard.sol";

contract QuestGuard is Ownable, IQuestGuard {

    uint16 public constant override maxAllocation = 10000;
    uint16 public override limitAllocation;

    event SetLimitAllocation(uint16 limitAllocation);
    event SetHoldingRewardToken(uint256 amount, uint16 increase);

    constructor(
        uint16 _limitAllocation
    ) {
        limitAllocation = _limitAllocation;
    }

    function canAllocate(
        uint256 _amount,
        uint256 _balanceOfWant,
        uint256 _balanceOfMasterChef
    ) external view override returns (bool) {
        if (limitAllocation == 0) {
            return true;
        }
        uint256 percentage = (_amount + (_balanceOfWant * maxAllocation)) / _balanceOfMasterChef;
        return percentage <= limitAllocation;
    }

    function setLimitAllocation(uint16 _limitAllocation) external onlyOwner {
        require(_limitAllocation <= maxAllocation, "invalid limit");

        limitAllocation = _limitAllocation;
        emit SetLimitAllocation(_limitAllocation);
    }
}
