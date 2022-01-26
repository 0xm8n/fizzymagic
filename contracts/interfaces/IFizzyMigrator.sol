// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IFizzyMigrator {
    function migrate(
        address token,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external;
}
