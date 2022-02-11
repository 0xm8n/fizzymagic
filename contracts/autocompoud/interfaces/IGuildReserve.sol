// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IGuildReserve {
    function balances() external view returns (uint256);

    function withdraw(address to, uint256 amount) external returns (uint256);
}
