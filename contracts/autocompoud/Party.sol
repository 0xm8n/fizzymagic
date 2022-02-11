// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IParty.sol";
import "./interfaces/IQuest.sol";
import "./interfaces/IQuestGuard.sol";
import "./interfaces/IWithdrawFee.sol";
import "../utils/Math.sol";

contract Party is IParty, Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant maxWithdrawFee = 1000; // 10%

    address public immutable override guild;
    IQuest public override quest;
    IERC20 public immutable override questToken;
    uint256 public override totalSupply;

    address public override feeWithdraw;
    address public override gaurdAlloc;
    address public tva;

    event UpgradeQuest(address implementation);
    event SetWithdrawFee(address npc);
    event SetQuestGuard(address npc);
    event SetTVA(address tva);

    constructor(
        address _guild,
        IQuest _quest,
        address _tva
    ) {
        guild = _guild;
        quest = _quest;
        questToken = IERC20(quest.questToken());
        tva = _tva;
    }

    modifier onlyGuild() {
        require(msg.sender == guild, "!guild");
        _;
    }

    function setWithdrawFee(address _feeWithdraw) external onlyOwner {
        feeWithdraw = _feeWithdraw;
        emit SetWithdrawFee(_feeWithdraw);
    }

    function setQuestGuard(address _gaurdAlloc) external onlyOwner {
        gaurdAlloc = _gaurdAlloc;
        emit SetQuestGuard(_gaurdAlloc);
    }

    function setTva(address _tva) external {
        require(tva == msg.sender, "!TVA");
        tva = _tva;
        emit SetTVA(_tva);
    }

    /**
     * @dev It calculates the total underlying value of {token} held by the system.
     * It takes into account the party contract balance, the quest contract balance
     *  and the balance deployed in other contracts as part of the quest.
     */
    function balance() public view override returns (uint256) {
        return questToken.balanceOf(address(this)) + quest.balanceOf();
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
            gaurdAlloc == address(0) || IQuestGuard(gaurdAlloc).canAllocate(amount, quest.balanceOf(), quest.balanceOfMasterChef()),
            "capacity limit reached"
        );
    }

    function deposit(address user, uint256 amount) external override onlyGuild returns (uint256 loot) {
        quest.beforeDeposit();

        uint256 poolBefore = balance();
        questToken.safeTransferFrom(msg.sender, address(this), amount);
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
     * @dev Function to send funds into the quest and put them to work. It's primarily called
     * by the party's deposit() function.
     */
    function earn() public {
        questToken.safeTransfer(address(quest), questToken.balanceOf(address(this)));
        quest.deposit();
    }

    /**
     * @param loot amount of user's share
     */
    function _withdraw(address user, uint256 loot) private returns (uint256) {
        uint256 r = (balance() * loot) / totalSupply;
        totalSupply -= loot;

        uint256 b = questToken.balanceOf(address(this));
        if (b < r) {
            uint256 amount = r - b;
            quest.withdraw(amount);
            uint256 _after = questToken.balanceOf(address(this));
            uint256 diff = _after - b;
            if (diff < amount) {
                r = b + diff;
            }
        }

        uint256 fee = calculateWithdrawFee(r);
        if (fee > 0) {
            r -= fee;
            questToken.safeTransfer(address(feeWithdraw), fee);
            IWithdrawFee(feeWithdraw).distributeWithdrawFee(questToken);
        }
        questToken.safeTransfer(msg.sender, r);
        return r;
    }

    function withdraw(address user, uint256 loot) external override onlyGuild returns (uint256) {
        return _withdraw(user, loot);
    }

    function upgradeQuest(address implementation) external {
        require(tva == msg.sender, "!TVA");
        require(address(this) == IQuest(implementation).party(), "invalid quest");
        require(questToken == IERC20(quest.questToken()), "invalid quest questToken");

        // retire old quest
        quest.retireQuest();

        // new quest
        quest = IQuest(implementation);
        earn();

        emit UpgradeQuest(implementation);
    }

    /**
     * @dev Rescues random funds stuck that the strat can't handle.
     * @param token address of the token to rescue.
     */
    function inCaseTokensGetStuck(address token) external onlyOwner {
        require(token != address(questToken), "!questToken");

        uint256 amount = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
