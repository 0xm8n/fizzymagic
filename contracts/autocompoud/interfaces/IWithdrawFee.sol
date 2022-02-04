// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWithdrawFee {
    function maxFee() external view returns (uint256);

    function withdrawFee() external view returns (uint256);

    function treasuryFeeWithdraw() external view returns (uint256);

    function calculateWithdrawFee(uint256 _strategyTokenAmount) external view returns (uint256);

    function distributeWithdrawFee(IERC20 _token) external;

    function ignoreFee(bool enable) external;

}
