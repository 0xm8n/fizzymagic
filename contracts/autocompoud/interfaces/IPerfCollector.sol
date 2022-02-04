// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IPerfCollector {
    function maxPerfFee() external view returns (uint256);

    function perfFee() external view returns (uint256);

    function callFee() external view returns (uint256);
}
