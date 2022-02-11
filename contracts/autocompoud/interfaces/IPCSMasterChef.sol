//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IPcsMasterChef {
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    struct PoolInfo {
        address lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accCakePerShare;
    }

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function enterStaking(uint256 _amount) external;

    function leaveStaking(uint256 _amount) external;

    function pendingCake(uint256 _pid, address _user) external view returns (uint256);

    function userInfo(uint256 _pid, address _user) external view returns (UserInfo memory);

    function poolInfo(uint256 _pid) external view returns (PoolInfo memory);

    function emergencyWithdraw(uint256 _pid) external;
}