// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface IOldFizzyFactory {
    function getExchange(address) external view returns (address);
}
