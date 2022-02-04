// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IBaseStrategy.sol";
import "./interfaces/IGasPrice.sol";

abstract contract BaseStrategy is Ownable, Pausable, IBaseStrategy {
    address public guild;
    address public unirouter;
    address public override leader;
    address public treasuryFeeRecipient;
    address public harvester;

    address public gasPrice = 0xc558252b50920a21f4AE3225E1Ed7D250E5D5593;

    event SetGuild(address guild);
    event SetRouter(address router);
    event SetTreasuryFeeRecipient(address treasuryFeeRecipient);
    event SetHarvester(address harvester);
    event SetGasPrice(address gasPrice);

    constructor(
        address _guild,
        address _unirouter,
        address _leader,
        address _treasuryFeeRecipient,
        address _harvester
    ) {
        guild = _guild;
        unirouter = _unirouter;
        leader = _leader;
        treasuryFeeRecipient = _treasuryFeeRecipient;
        harvester = _harvester;
    }

    // checks that caller is either owner or guild.
    modifier onlyGuild() {
        require(msg.sender == owner() || msg.sender == guild, "!guild");
        _;
    }

    // verifies that the caller is not a contract.
    modifier onlyEOA() {
        require(msg.sender == tx.origin, "!EOA");
        _;
    }

    modifier onlyLeader() {
        require(msg.sender == leader, "!leader");
        _;
    }

    modifier onlyEOAandLeader() {
        require(tx.origin == msg.sender || msg.sender == leader, "!contract");
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

    function setGuild(address _guild) external onlyGuild {
        guild = _guild;
        emit SetGuild(_guild);
    }

    function setUnirouter(address _unirouter) external onlyOwner {
        unirouter = _unirouter;
        emit SetRouter(_unirouter);
    }

    function setLeader(address _leader) external onlyOwner {
        require(leader == address(0), "already set");
        leader = _leader;
    }

    function setTreasuryFeeRecipient(address _treasuryFeeRecipient) external onlyOwner {
        treasuryFeeRecipient = _treasuryFeeRecipient;
        emit SetTreasuryFeeRecipient(_treasuryFeeRecipient);
    }

    function setHarvester(address _harvester) external onlyOwner {
        harvester = _harvester;
        emit SetHarvester(_harvester);
    }

    function setGasPrice(address _gasPrice) external onlyGuild {
        gasPrice = _gasPrice;
        emit SetGasPrice(_gasPrice);
    }
}
