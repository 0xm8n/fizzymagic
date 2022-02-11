// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "./interfaces/IPerfCollector.sol";
import "./QuestBase.sol";

abstract contract PerfCollector is QuestBase, IPerfCollector {
    uint256 public constant override maxPerfFee = 10000;
    uint256 public override perfFee = 300; // 3%
    uint256 public constant maxTotalPerfFee = 1000; // 10%

    uint256 public override callFee = 4000; // 40% of total fee
    uint256 public treasuryFee = 6000; // 60% of total fee
    uint256 public feeSum = 10000;

    event SetTotalFee(uint256 perfFee);
    event SetCallFee(uint256 fee);
    event SetTreasuryFee(uint256 fee);
    event SetRewardTokenFee(uint256 fee);

    function setTotalFee(uint256 _perfFee) external onlyOwner {
        require(_perfFee <= maxTotalPerfFee, "!cap");

        perfFee = _perfFee;
        emit SetTotalFee(_perfFee);
    }

    function setCallFee(uint256 _fee) external onlyOwner {
        callFee = _fee;
        feeSum = callFee + treasuryFee;
        emit SetCallFee(_fee);
    }

    function setTreasuryFee(uint256 _fee) external onlyOwner {
        treasuryFee = _fee;
        feeSum = callFee + treasuryFee;
        emit SetTreasuryFee(_fee);
    }
}
