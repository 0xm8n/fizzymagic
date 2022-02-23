//SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IAllocKafraV2.sol";

contract AllocKafraV2 is Ownable, IAllocKafraV2 {
    uint16 public constant override MAX_ALLOCATION = 10000;
    uint16 public override limitAllocation;
    uint256 public holdingKSW;
    uint16 public holdingKSWAllocationIncrease;
    address public immutable ksw;

    event SetLimitAllocation(uint16 limitAllocation);
    event SetHoldingKSW(uint256 amount, uint16 increase);

    constructor(
        address _ksw,
        uint16 _limitAllocation,
        uint256 _holdingKSW,
        uint16 _holdingKSWAllocationIncrease
    ) {
        ksw = _ksw;
        limitAllocation = _limitAllocation;
        holdingKSW = _holdingKSW;
        holdingKSWAllocationIncrease = _holdingKSWAllocationIncrease;
    }

    function isHoldingKSW(address user) public view returns (bool) {
        if (holdingKSW == 0) {
            return false;
        }

        uint256 bal = IERC20(ksw).balanceOf(user);
        return bal >= holdingKSW;
    }

    function canAllocate(
        uint256,
        uint256 _balanceOfWant,
        uint256 _balanceOfMasterChef,
        address user
    ) external view override returns (bool) {
        if (limitAllocation == 0) {
            return true;
        }
        uint256 percentage = (_balanceOfWant * MAX_ALLOCATION) / _balanceOfMasterChef;
        if (isHoldingKSW(user)) {
            return percentage <= limitAllocation + holdingKSWAllocationIncrease;
        }
        return percentage <= limitAllocation;
    }

    function setLimitAllocation(uint16 _limitAllocation) external onlyOwner {
        require(_limitAllocation <= MAX_ALLOCATION, "invalid limit");

        limitAllocation = _limitAllocation;
        emit SetLimitAllocation(_limitAllocation);
    }

    function setHoldingKSW(uint256 amount, uint16 increase) external onlyOwner {
        holdingKSW = amount;
        holdingKSWAllocationIncrease = increase;
        emit SetHoldingKSW(amount, increase);
    }

    function userLimitAllocation(address user) external view override returns (uint16) {
        if (isHoldingKSW(user)) {
            return limitAllocation + holdingKSWAllocationIncrease;
        }
        return limitAllocation;
    }
}