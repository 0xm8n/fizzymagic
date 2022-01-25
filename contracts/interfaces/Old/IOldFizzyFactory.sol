// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IOldFizzyFactory {
    function getExchange(address) external view returns (address);
}
