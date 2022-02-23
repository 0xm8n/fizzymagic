//SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IPronteraReserve {
    function balances() external view returns (uint256);

    function withdraw(address to, uint256 amount) external returns (uint256);
}