// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IFizzyMigrator {
    function migrate(address token, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external;
}
