// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IQuestGuard {
    function maxAllocation() external view returns (uint16);

    function limitAllocation() external view returns (uint16);

    function canAllocate(
        uint256 _amount,
        uint256 _balanceOfWant,
        uint256 _balanceOfMasterChef
    ) external view returns (bool);
}
