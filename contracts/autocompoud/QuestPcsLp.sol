// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./PerfCollector.sol";
import "./QuestBase.sol";
import "./interfaces/IQuest.sol";
import "./interfaces/IPcsMasterChef.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Router02.sol";

contract QuestPcsLp is QuestBase {
    using SafeERC20 for IERC20;
    using Address for address payable;

    // Tokens used
    address public constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address public constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E; // CAKE ROUTER
    address public constant MASTERCHEF = 0x73feaa1eE314F8c655E354234017bE2193C9E24E;

    constructor(
        address _guild,
        address _guildReserve,
        address _executor,
        address _operator,
        uint256 _pid,
        address[] memory _cakeToLp0Route,
        address[] memory _cakeToLp1Route
    ) QuestBase( ROUTER, _guild, _guildReserve, _executor, _operator, MASTERCHEF, IPcsMasterChef(MASTERCHEF).poolInfo(_pid).lpToken, _pid, CAKE, _cakeToLp0Route, _cakeToLp1Route){}

    /**
     * @dev Function to synchronize balances before new user deposit.
     */
    function beforeDeposit() external override {}

    // puts the funds to work
    function deposit() public override whenNotPaused {
        uint256 questLpBal = IERC20(questLp).balanceOf(address(this));

        if (questLpBal > 0) {
            IPcsMasterChef(MASTERCHEF).deposit(pid, questLpBal);
        }
    }

    function withdraw(uint256 _amount) external override onlyParty {
        uint256 questLpBal = IERC20(questLp).balanceOf(address(this));

        if (questLpBal < _amount) {
            IPcsMasterChef(MASTERCHEF).withdraw(pid, _amount - questLpBal);
            questLpBal = IERC20(questLp).balanceOf(address(this));
        }

        if (questLpBal > _amount) {
            questLpBal = _amount;
        }

        IERC20(questLp).safeTransfer(party, questLpBal);
    }

    // compounds earnings and charges performance fee
    function harvest() external override whenNotPaused onlyEOA onlyHarvester gasThrottle {
        IPcsMasterChef(MASTERCHEF).deposit(pid, 0);
        chargeFees();
        addLiquidity();
        deposit();

        emit Harvest(msg.sender);
    }

    // it calculates how much 'questLp' the quest has working in the farm.
    function balanceOfPool() public view override returns (uint256) {
        return IPcsMasterChef(MASTERCHEF).userInfo(pid, address(this)).amount;
    }

    function pendingRewardTokens() external view override returns (IERC20[] memory rewardTokens, uint256[] memory rewardAmounts) {
        rewardTokens = new IERC20[](1);
        rewardAmounts = new uint256[](1);
        rewardTokens[0] = IERC20(CAKE);
        rewardAmounts[0] = IPcsMasterChef(MASTERCHEF).pendingCake(pid, address(this)) + IERC20(CAKE).balanceOf(address(this));
    }

    // called as part of quest migration. Sends all the available funds back to the vault.
    function retireQuest() external override onlyParty {
        IPcsMasterChef(MASTERCHEF).emergencyWithdraw(pid);

        uint256 questLpBal = IERC20(questLp).balanceOf(address(this));
        IERC20(questLp).transfer(party, questLpBal);
    }

    // pauses deposits and withdraws all funds from third guild systems.
    function panic() external override onlyOperator {
        pause();
        IPcsMasterChef(MASTERCHEF).emergencyWithdraw(pid);
    }
}
