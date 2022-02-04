// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GasPrice is Ownable {
    uint256 public maxGasPrice = 5 gwei;

    event NewMaxGasPrice(uint256 oldPrice, uint256 newPrice);

    function setMaxGasPrice(uint256 _maxGasPrice) external onlyOwner {
        maxGasPrice = _maxGasPrice;
        emit NewMaxGasPrice(maxGasPrice, _maxGasPrice);
    }
}
