// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IQuestBase.sol";
import "./interfaces/IGasPrice.sol";

abstract contract QuestBase is Ownable, Pausable, IQuestBase {
    address public operator;
    address public unirouter;
    address public override party;
    address public treasuryFeeRecipient;
    address public harvester;
    address public gasPrice = 0xc558252b50920a21f4AE3225E1Ed7D250E5D5593;

    event SetOperator(address operator);
    event SetRouter(address router);
    event SetTreasuryFeeRecipient(address treasuryFeeRecipient);
    event SetHarvester(address harvester);
    event SetGasPrice(address gasPrice);

    constructor(
        address _operator,
        address _unirouter,
        address _party,
        address _treasuryFeeRecipient,
        address _harvester
    ) {
        operator = _operator;
        unirouter = _unirouter;
        party = _party;
        treasuryFeeRecipient = _treasuryFeeRecipient;
        harvester = _harvester;
    }

    // checks that caller is either owner or operator.
    modifier onlyOperator() {
        require(msg.sender == owner() || msg.sender == operator, "!operator");
        _;
    }

    // verifies that the caller is not a contract.
    modifier onlyEOA() {
        require(msg.sender == tx.origin, "!EOA");
        _;
    }

    modifier onlyParty() {
        require(msg.sender == party, "!party");
        _;
    }

    modifier onlyEOAandParty() {
        require(tx.origin == msg.sender || msg.sender == party, "!contract");
        _;
    }

    modifier onlyHarvester() {
        require(harvester == address(0) || msg.sender == harvester, "!harvester");
        _;
    }

    modifier gasThrottle() {
        require(tx.gasprice <= IGasPrice(gasPrice).maxGasPrice(), "gas is too high!");
        _;
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
        emit SetOperator(_operator);
    }

    function setUnirouter(address _unirouter) external onlyOwner {
        unirouter = _unirouter;
        emit SetRouter(_unirouter);
    }

    function setParty(address _party) external onlyOwner {
        require(party == address(0), "already set");
        party = _party;
    }

    function setTreasuryFeeRecipient(address _treasuryFeeRecipient) external onlyOwner {
        treasuryFeeRecipient = _treasuryFeeRecipient;
        emit SetTreasuryFeeRecipient(_treasuryFeeRecipient);
    }

    function setHarvester(address _harvester) external onlyOwner {
        harvester = _harvester;
        emit SetHarvester(_harvester);
    }

    function setGasPrice(address _gasPrice) external onlyOperator {
        gasPrice = _gasPrice;
        emit SetGasPrice(_gasPrice);
    }
}
