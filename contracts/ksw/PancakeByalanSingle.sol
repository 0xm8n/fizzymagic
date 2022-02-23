//SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IByalan.sol";
import "./ByalanIsland.sol";
import "./Sailor.sol";

contract PancakeByalanSingle is ByalanIsland, Sailor, IByalan {
    using SafeERC20 for IERC20;
    using Address for address payable;

    // Tokens used
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address public immutable override want;

    // Third party contracts
    address public constant MASTERCHEF = 0x73feaa1eE314F8c655E354234017bE2193C9E24E;
    uint256 public immutable pid;

    // Routes
    address[] public cakeToWbnbRoute;

    event Harvest(address indexed harvester);

    constructor(
        address _hydra,
        address _izlude,
        address _kswFeeRecipient,
        address _treasuryFeeRecipient,
        address _harvester,
        uint256 _pid
    )
        ByalanIsland(
            _hydra,
            0x10ED43C718714eb63d5aA57B78B54704E256024E,
            _izlude,
            _kswFeeRecipient,
            _treasuryFeeRecipient,
            _harvester
        )
    {
        pid = _pid;

        want = IMasterChef(MASTERCHEF).poolInfo(_pid).lpToken;

        cakeToWbnbRoute = [CAKE, WBNB];

        _giveAllowances();
    }

    /**
     * @dev Function to synchronize balances before new user deposit.
     */
    function beforeDeposit() external override onlyIzlude {
        _harvest();
    }

    // puts the funds to work
    function deposit() public override whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IMasterChef(MASTERCHEF).enterStaking(wantBal);
        }
    }

    function withdraw(uint256 _amount) external override onlyIzlude {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMasterChef(MASTERCHEF).leaveStaking(_amount - wantBal);
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        IERC20(want).safeTransfer(izlude, wantBal);
    }

    // compounds earnings and charges performance fee
    function harvest() external override whenNotPaused onlyEOA onlyHarvester gasThrottle {
        _harvest();
    }

    function _harvest() private {
        IMasterChef(MASTERCHEF).leaveStaking(0);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        if (wantBal > 0) {
            chargeFees();
            deposit();

            emit Harvest(msg.sender);
        }
    }

    // performance fees
    function chargeFees() internal {
        uint256 toBnb = (IERC20(CAKE).balanceOf(address(this)) * totalFee) / MAX_FEE;
        IUniswapV2Router02(unirouter).swapExactTokensForETH(toBnb, 0, cakeToWbnbRoute, address(this), block.timestamp);

        uint256 bnbBal = address(this).balance;

        uint256 callFeeAmount = (bnbBal * callFee) / feeSum;
        payable(tx.origin).sendValue(callFeeAmount);

        uint256 treasuryFeeAmount = (bnbBal * treasuryFee) / feeSum;
        payable(treasuryFeeRecipient).sendValue(treasuryFeeAmount);

        uint256 kswFeeAmount = (bnbBal * kswFee) / feeSum;
        payable(kswFeeRecipient).sendValue(kswFeeAmount);
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() external view override returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view override returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view override returns (uint256) {
        return IMasterChef(MASTERCHEF).userInfo(pid, address(this)).amount;
    }

    function balanceOfMasterChef() external view override returns (uint256) {
        return IERC20(want).balanceOf(MASTERCHEF);
    }

    function pendingRewardTokens()
        external
        view
        override
        returns (IERC20[] memory rewardTokens, uint256[] memory rewardAmounts)
    {
        rewardTokens = new IERC20[](1);
        rewardAmounts = new uint256[](1);
        rewardTokens[0] = IERC20(CAKE);
        rewardAmounts[0] =
            IMasterChef(MASTERCHEF).pendingCake(pid, address(this)) +
            IERC20(CAKE).balanceOf(address(this));
    }

    // called as part of strategy migration. Sends all the available funds back to the vault.
    function retireStrategy() external override onlyIzlude {
        IMasterChef(MASTERCHEF).emergencyWithdraw(pid);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(izlude, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() external override onlyHydra {
        pause();
        IMasterChef(MASTERCHEF).emergencyWithdraw(pid);
    }

    function pause() public override onlyHydra {
        _pause();

        _removeAllowances();
    }

    function unpause() external override onlyHydra {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function paused() public view override(IByalan, Pausable) returns (bool) {
        return super.paused();
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(MASTERCHEF, type(uint256).max);
        IERC20(CAKE).safeApprove(unirouter, type(uint256).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(MASTERCHEF, 0);
        IERC20(CAKE).safeApprove(unirouter, 0);
    }

    receive() external payable {
        require(msg.sender == unirouter, "reject");
    }
}