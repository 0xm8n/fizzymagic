// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IQuest.sol";

interface IParty {
    function totalSupply() external view returns (uint256);

    function guild() external view returns (address);

    function questToken() external view returns (IERC20);

    function deposit(address user, uint256 amount) external returns (uint256 loot);

    function withdraw(address user, uint256 loot) external returns (uint256);

    function balance() external view returns (uint256);

    function quest() external view returns (IQuest);

    function feeWithdraw() external view returns (address);

    function gaurdAlloc() external view returns (address);

    function calculateWithdrawFee(uint256 amount) external view returns (uint256);
}
