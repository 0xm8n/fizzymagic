//SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IFeeKafraV2.sol";

contract FeeKafraV2 is Ownable, IFeeKafraV2 {
    using SafeERC20 for IERC20;

    uint256 public constant override MAX_FEE = 10000;

    uint256 public constant MAX_WITHDRAW_FEE = 1000; // 10%
    uint256 public override withdrawFee = 20; // 0.2 %
    uint256 public override treasuryFeeWithdraw = 5000; // 50% of total fee
    uint256 public override kswFeeWithdraw = 5000; // 50% of total fee
    uint256 public holdingKSW = 1500 ether;
    uint256 public holdingKSWWithdrawFee = 10; // 0.1 %
    uint256 public holdingKSWGod = 10000 ether;
    uint256 public holdingKSWGodWithdrawFee = 5; // 0.05 %

    address public immutable ksw;

    address public kswFeeRecipient;
    address public treasuryFeeRecipient;

    mapping(address => bool) public allowIgnoreFeeCaller;
    uint256 private ignoreFeeBlock;

    event SetWithdrawFee(uint256 fee);
    event SetTreasuryFeeWithdraw(uint256 fee);
    event SetKSWFeeWithdraw(uint256 fee);
    event SetKSWFeeRecipient(address to);
    event SetTreasuryFeeRecipient(address to);
    event SetHoldingKSW(uint256 amount);
    event SetHoldingKSWWithdrawFee(uint256 fee);
    event SetHoldingKSWGod(uint256 amount);
    event SetHoldingKSWGodWithdrawFee(uint256 fee);
    event SetAllowIgnoreFeeCaller(address addr, bool allow);

    constructor(
        address _ksw,
        address _kswFeeRecipient,
        address _treasuryFeeRecipient
    ) {
        ksw = _ksw;
        kswFeeRecipient = _kswFeeRecipient;
        treasuryFeeRecipient = _treasuryFeeRecipient;
    }

    function userBalance(address _user) public view returns (uint256) {
        uint256 bal = IERC20(ksw).balanceOf(_user);
        return bal;
    }

    function isHoldingKSW(address _user) public view returns (bool) {
        if (holdingKSW == 0) {
            return false;
        }

        uint256 bal = userBalance(_user);
        return bal >= holdingKSW;
    }

    function isGod(address _user) public view returns (bool) {
        if (holdingKSWGod == 0) {
            return false;
        }

        uint256 bal = userBalance(_user);
        return bal >= holdingKSWGod;
    }

    function setHoldingKSW(uint256 _amount) external onlyOwner {
        holdingKSW = _amount;
        emit SetHoldingKSW(_amount);
    }

    function setHoldingKSWGod(uint256 _amount) external onlyOwner {
        holdingKSWGod = _amount;
        emit SetHoldingKSWGod(_amount);
    }

    function userWithdrawFee(address _user) public view override returns (uint256) {
        if (isGod(_user)) {
            return holdingKSWGodWithdrawFee;
        }
        if (isHoldingKSW(_user)) {
            return holdingKSWWithdrawFee;
        }
        return withdrawFee;
    }

    function calculateWithdrawFee(uint256 _wantAmount, address _user) external view override returns (uint256) {
        if (ignoreFeeBlock == block.number) {
            return 0;
        }

        return (_wantAmount * userWithdrawFee(_user)) / MAX_FEE;
    }

    function setWithdrawFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_WITHDRAW_FEE, "!cap");

        withdrawFee = _fee;
        emit SetWithdrawFee(_fee);
    }

    function setHoldingKSWWithdrawFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_WITHDRAW_FEE, "!cap");

        holdingKSWWithdrawFee = _fee;
        emit SetHoldingKSWWithdrawFee(_fee);
    }

    function setHoldingKSWGodWithdrawFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_WITHDRAW_FEE, "!cap");

        holdingKSWGodWithdrawFee = _fee;
        emit SetHoldingKSWGodWithdrawFee(_fee);
    }

    function setTreasuryFeeWithdraw(uint256 _fee) external onlyOwner {
        treasuryFeeWithdraw = _fee;
        emit SetTreasuryFeeWithdraw(_fee);
    }

    function setKSWFeeWithdraw(uint256 _fee) external onlyOwner {
        kswFeeWithdraw = _fee;
        emit SetKSWFeeWithdraw(_fee);
    }

    function setKSWFeeRecipient(address _to) external onlyOwner {
        kswFeeRecipient = _to;
        emit SetKSWFeeRecipient(_to);
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

    function distributeWithdrawFee(IERC20 _token, address _user) external override {
        uint256 feeAmount = _token.balanceOf(address(this));

        uint256 treasuryFeeAmount;
        uint256 kswFeeAmount;
        if (isGod(_user)) {
            uint256 withdrawFeeSum = treasuryFeeWithdraw + holdingKSWGodWithdrawFee;
            treasuryFeeAmount = (feeAmount * treasuryFeeWithdraw) / withdrawFeeSum;
            kswFeeAmount = (feeAmount * holdingKSWGodWithdrawFee) / withdrawFeeSum;
        } else if (isHoldingKSW(_user)) {
            uint256 withdrawFeeSum = treasuryFeeWithdraw + holdingKSWWithdrawFee;
            treasuryFeeAmount = (feeAmount * treasuryFeeWithdraw) / withdrawFeeSum;
            kswFeeAmount = (feeAmount * holdingKSWWithdrawFee) / withdrawFeeSum;
        } else {
            uint256 withdrawFeeSum = treasuryFeeWithdraw + kswFeeWithdraw;
            treasuryFeeAmount = (feeAmount * treasuryFeeWithdraw) / withdrawFeeSum;
            kswFeeAmount = (feeAmount * kswFeeWithdraw) / withdrawFeeSum;
        }

        if (treasuryFeeAmount > 0) {
            _token.safeTransfer(treasuryFeeRecipient, treasuryFeeAmount);
        }
        if (kswFeeAmount > 0) {
            _token.safeTransfer(kswFeeRecipient, kswFeeAmount);
        }
    }
}