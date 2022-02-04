// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./PerfCollector.sol";
import "./BaseStrategy.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IPCSMasterChef.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Router02.sol";

contract PCSStrategyLP is BaseStrategy, PerfCollector, IStrategy {
    using SafeERC20 for IERC20;
    using Address for address payable;

    // Tokens used
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address public constant PCS_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address public immutable override strategyToken;
    address public immutable lpToken0;
    address public immutable lpToken1;

    // Third party contracts
    address public constant MASTERCHEF = 0x73feaa1eE314F8c655E354234017bE2193C9E24E;
    uint256 public immutable pid;

    // Routes
    address[] public cakeToWbnbRoute;
    address[] public cakeToLp0Route;
    address[] public cakeToLp1Route;

    event Harvest(address indexed harvester);

    constructor(
        address _guild,
        address _leader,
        address _treasuryFeeRecipient,
        address _harvester,
        uint256 _pid,
        address[] memory _cakeToLp0Route,
        address[] memory _cakeToLp1Route
    ) BaseStrategy(_guild, PCS_ROUTER, _leader, _treasuryFeeRecipient, _harvester) {
        pid = _pid;

        strategyToken = IPCSMasterChef(MASTERCHEF).poolInfo(_pid).lpToken;
        lpToken0 = IUniswapV2Pair(strategyToken).token0();
        lpToken1 = IUniswapV2Pair(strategyToken).token1();

        cakeToWbnbRoute = [CAKE, WBNB];
        if (lpToken0 != CAKE) {
            require(_cakeToLp0Route[0] == CAKE, "invalid lp 0 route");
            require(_cakeToLp0Route[_cakeToLp0Route.length - 1] == lpToken0, "invalid lp 0 route");
            require(
                IUniswapV2Router02(unirouter).getAmountsOut(1 ether, _cakeToLp0Route)[_cakeToLp0Route.length - 1] > 0,
                "invalid lp 0 route"
            );
            cakeToLp0Route = _cakeToLp0Route;
        }

        if (lpToken1 != CAKE) {
            require(_cakeToLp1Route[0] == CAKE, "invalid lp 1 route");
            require(_cakeToLp1Route[_cakeToLp1Route.length - 1] == lpToken1, "invalid lp 1 route");
            require(
                IUniswapV2Router02(unirouter).getAmountsOut(1 ether, _cakeToLp1Route)[_cakeToLp1Route.length - 1] > 0,
                "invalid lp 1 route"
            );
            cakeToLp1Route = _cakeToLp1Route;
        }

        _giveAllowances();
    }

    /**
     * @dev Function to synchronize balances before new user deposit.
     */
    function beforeDeposit() external override {}

    // puts the funds to work
    function deposit() public override whenNotPaused {
        uint256 strategyTokenBal = IERC20(strategyToken).balanceOf(address(this));

        if (strategyTokenBal > 0) {
            IPCSMasterChef(MASTERCHEF).deposit(pid, strategyTokenBal);
        }
    }

    function withdraw(uint256 _amount) external override onlyLeader {
        uint256 strategyTokenBal = IERC20(strategyToken).balanceOf(address(this));

        if (strategyTokenBal < _amount) {
            IPCSMasterChef(MASTERCHEF).withdraw(pid, _amount - strategyTokenBal);
            strategyTokenBal = IERC20(strategyToken).balanceOf(address(this));
        }

        if (strategyTokenBal > _amount) {
            strategyTokenBal = _amount;
        }

        IERC20(strategyToken).safeTransfer(leader, strategyTokenBal);
    }

    // compounds earnings and charges performance fee
    function harvest() external override whenNotPaused onlyEOA onlyHarvester gasThrottle {
        IPCSMasterChef(MASTERCHEF).deposit(pid, 0);
        chargeFees();
        addLiquidity();
        deposit();

        emit Harvest(msg.sender);
    }

    // performance fees
    function chargeFees() internal {
        uint256 toBnb = (IERC20(CAKE).balanceOf(address(this)) * perfFee) / maxPerfFee;
        IUniswapV2Router02(unirouter).swapExactTokensForETH(toBnb, 0, cakeToWbnbRoute, address(this), block.timestamp);

        uint256 bnbBal = address(this).balance;

        uint256 callFeeAmount = (bnbBal * callFee) / feeSum;
        payable(msg.sender).sendValue(callFeeAmount);

        uint256 treasuryFeeAmount = (bnbBal * treasuryFee) / feeSum;
        payable(treasuryFeeRecipient).sendValue(treasuryFeeAmount);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 cakeHalf = IERC20(CAKE).balanceOf(address(this)) / 2;

        if (lpToken0 != CAKE) {
            IUniswapV2Router02(unirouter).swapExactTokensForTokens(cakeHalf, 0, cakeToLp0Route, address(this), block.timestamp);
        }

        if (lpToken1 != CAKE) {
            IUniswapV2Router02(unirouter).swapExactTokensForTokens(cakeHalf, 0, cakeToLp1Route, address(this), block.timestamp);
        }

        IUniswapV2Router02(unirouter).addLiquidity(
            lpToken0,
            lpToken1,
            IERC20(lpToken0).balanceOf(address(this)),
            IERC20(lpToken1).balanceOf(address(this)),
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    // calculate the total underlaying 'strategyToken' held by the strat.
    function balanceOf() external view override returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'strategyToken' this contract holds.
    function balanceOfWant() public view override returns (uint256) {
        return IERC20(strategyToken).balanceOf(address(this));
    }

    // it calculates how much 'strategyToken' the strategy has working in the farm.
    function balanceOfPool() public view override returns (uint256) {
        return IPCSMasterChef(MASTERCHEF).userInfo(pid, address(this)).amount;
    }

    function balanceOfMasterChef() external view override returns (uint256) {
        return IERC20(strategyToken).balanceOf(MASTERCHEF);
    }

    function pendingRewardTokens() external view override returns (IERC20[] memory rewardTokens, uint256[] memory rewardAmounts) {
        rewardTokens = new IERC20[](1);
        rewardAmounts = new uint256[](1);
        rewardTokens[0] = IERC20(CAKE);
        rewardAmounts[0] = IPCSMasterChef(MASTERCHEF).pendingCake(pid, address(this)) + IERC20(CAKE).balanceOf(address(this));
    }

    // called as part of strategy migration. Sends all the available funds back to the vault.
    function retireStrategy() external override onlyLeader {
        IPCSMasterChef(MASTERCHEF).emergencyWithdraw(pid);

        uint256 strategyTokenBal = IERC20(strategyToken).balanceOf(address(this));
        IERC20(strategyToken).transfer(leader, strategyTokenBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() external override onlyGuild {
        pause();
        IPCSMasterChef(MASTERCHEF).emergencyWithdraw(pid);
    }

    function pause() public override onlyGuild {
        _pause();

        _removeAllowances();
    }

    function unpause() external override onlyGuild {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function paused() public view override(IStrategy, Pausable) returns (bool) {
        return super.paused();
    }

    function _giveAllowances() internal {
        IERC20(strategyToken).safeApprove(MASTERCHEF, type(uint256).max);
        IERC20(CAKE).safeApprove(unirouter, type(uint256).max);

        // lp token 0 and 1 maybe cake so approve 0 is needed here
        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, type(uint256).max);

        IERC20(lpToken1).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, type(uint256).max);
    }

    function _removeAllowances() internal {
        IERC20(strategyToken).safeApprove(MASTERCHEF, 0);
        IERC20(CAKE).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);
    }

    receive() external payable {
        require(msg.sender == unirouter, "reject");
    }
}
