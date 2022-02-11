// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IWithdrawFee.sol";

contract WithdrawFee is Ownable, IWithdrawFee {
    using SafeERC20 for IERC20;
    
    uint256 public constant override maxFee = 10000;
    uint256 public constant maxWithdrawFee = 1000; // 10%

    uint256 public override withdrawFee = 20; // 0.2 %
    uint256 public override treasuryFeeWithdraw = 5000; // 50% of total fee

    address public treasuryFeeRecipient;

    mapping(address => bool) public allowIgnoreFeeCaller;
    uint256 private ignoreFeeBlock;

    event SetWithdrawFee(uint256 fee);
    event SetTreasuryFeeWithdraw(uint256 fee);
    event SetTreasuryFeeRecipient(address to);
    event SetAllowIgnoreFeeCaller(address addr, bool allow);

    constructor(
        address _treasuryFeeRecipient
    ) {
        treasuryFeeRecipient = _treasuryFeeRecipient;
    }

    function calculateWithdrawFee(uint256 _questTokenAmount) external view override returns (uint256) {
        if (ignoreFeeBlock == block.number) {
            return 0;
        }

        return (_questTokenAmount / maxFee);
    }

    function setWithdrawFee(uint256 _fee) external onlyOwner {
        require(_fee <= maxWithdrawFee, "!cap");

        withdrawFee = _fee;
        emit SetWithdrawFee(_fee);
    }

    function setTreasuryFeeWithdraw(uint256 _fee) external onlyOwner {
        treasuryFeeWithdraw = _fee;
        emit SetTreasuryFeeWithdraw(_fee);
    }

    function setTreasuryFeeRecipient(address _to) external onlyOwner {
        treasuryFeeRecipient = _to;
        emit SetTreasuryFeeRecipient(_to);
    }

    function setAllowIgnoreFeeCaller(address _to, bool _allow) external onlyOwner {
        allowIgnoreFeeCaller[_to] = _allow;
        emit SetAllowIgnoreFeeCaller(_to, _allow);
    }

    // caller to ignoreFee *MUST* call ignoreFee(false) to reset state
    function ignoreFee(bool enable) external {
        require(allowIgnoreFeeCaller[msg.sender], "!allow");

        if (enable) {
            // in-case caller forgot to reset state, we reduce impact to 1 block
            ignoreFeeBlock = block.number;
            return;
        }
        ignoreFeeBlock = 0;
    }

    function distributeWithdrawFee(IERC20 _token) external override {
        uint256 feeAmount = _token.balanceOf(address(this));
        _token.safeTransfer(treasuryFeeRecipient, feeAmount);
    }
}
