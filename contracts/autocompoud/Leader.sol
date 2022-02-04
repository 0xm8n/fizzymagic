// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ILeader.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IFarmGuard.sol";
import "./interfaces/IWithdrawFee.sol";
import "../utils/Math.sol";

contract Leader is ILeader, Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant maxWithdrawFee = 1000; // 10%

    address public immutable override party;
    IStrategy public override strategy;
    IERC20 public immutable override strategyToken;
    uint256 public override totalSupply;

    address public override feeWithdraw;
    address public override gaurdAlloc;
    address public tva;

    event UpgradeStrategy(address implementation);
    event SetWithdrawFee(address npc);
    event SetFarmGuard(address npc);
    event SetTVA(address tva);

    constructor(
        address _party,
        IStrategy _strategy,
        address _tva
    ) {
        party = _party;
        strategy = _strategy;
        strategyToken = IERC20(strategy.strategyToken());
        tva = _tva;
    }

    modifier onlyParty() {
        require(msg.sender == party, "!party");
        _;
    }

    function setWithdrawFee(address _feeWithdraw) external onlyOwner {
        feeWithdraw = _feeWithdraw;
        emit SetWithdrawFee(_feeWithdraw);
    }

    function setFarmGuard(address _gaurdAlloc) external onlyOwner {
        gaurdAlloc = _gaurdAlloc;
        emit SetFarmGuard(_gaurdAlloc);
    }

    function setTva(address _tva) external {
        require(tva == msg.sender, "!TVA");
        tva = _tva;
        emit SetTVA(_tva);
    }

    /**
     * @dev It calculates the total underlying value of {token} held by the system.
     * It takes into account the leader contract balance, the strategy contract balance
     *  and the balance deployed in other contracts as part of the strategy.
     */
    function balance() public view override returns (uint256) {
        return strategyToken.balanceOf(address(this)) + strategy.balanceOf();
    }

    function calculateWithdrawFee(uint256 amount) public view override returns (uint256) {
        if (feeWithdraw == address(0)) {
            return 0;
        }
        return Math.min(IWithdrawFee(feeWithdraw).calculateWithdrawFee(amount), _calculateMaxWithdrawFee(amount));
    }

    function _calculateMaxWithdrawFee(uint256 amount) private pure returns (uint256) {
        return (amount * maxWithdrawFee) / 10000;
    }

    function checkAllocation(uint256 amount) private view {
        require(
            gaurdAlloc == address(0) || IFarmGuard(gaurdAlloc).canAllocate(amount, strategy.balanceOf(), strategy.balanceOfMasterChef()),
            "capacity limit reached"
        );
    }

    function deposit(address user, uint256 amount) external override onlyParty returns (uint256 loot) {
        strategy.beforeDeposit();

        uint256 poolBefore = balance();
        strategyToken.safeTransferFrom(msg.sender, address(this), amount);
        earn();
        checkAllocation(amount);

        if (totalSupply == 0) {
            loot = amount;
        } else {
            loot = (amount * totalSupply) / poolBefore;
        }
        totalSupply += loot;
    }

    /**
     * @dev Function to send funds into the strategy and put them to work. It's primarily called
     * by the leader's deposit() function.
     */
    function earn() public {
        strategyToken.safeTransfer(address(strategy), strategyToken.balanceOf(address(this)));
        strategy.deposit();
    }

    /**
     * @param loot amount of user's share
     */
    function _withdraw(address user, uint256 loot) private returns (uint256) {
        uint256 r = (balance() * loot) / totalSupply;
        totalSupply -= loot;

        uint256 b = strategyToken.balanceOf(address(this));
        if (b < r) {
            uint256 amount = r - b;
            strategy.withdraw(amount);
            uint256 _after = strategyToken.balanceOf(address(this));
            uint256 diff = _after - b;
            if (diff < amount) {
                r = b + diff;
            }
        }

        uint256 fee = calculateWithdrawFee(r);
        if (fee > 0) {
            r -= fee;
            strategyToken.safeTransfer(address(feeWithdraw), fee);
            IWithdrawFee(feeWithdraw).distributeWithdrawFee(strategyToken);
        }
        strategyToken.safeTransfer(msg.sender, r);
        return r;
    }

    function withdraw(address user, uint256 loot) external override onlyParty returns (uint256) {
        return _withdraw(user, loot);
    }

    function upgradeStrategy(address implementation) external {
        require(tva == msg.sender, "!TVA");
        require(address(this) == IStrategy(implementation).leader(), "invalid strategy");
        require(strategyToken == IERC20(strategy.strategyToken()), "invalid strategy strategyToken");

        // retire old strategy
        strategy.retireStrategy();

        // new strategy
        strategy = IStrategy(implementation);
        earn();

        emit UpgradeStrategy(implementation);
    }

    /**
     * @dev Rescues random funds stuck that the strat can't handle.
     * @param token address of the token to rescue.
     */
    function inCaseTokensGetStuck(address token) external onlyOwner {
        require(token != address(strategyToken), "!strategyToken");

        uint256 amount = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
