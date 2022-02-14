// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IGuildReserve.sol";
import "./interfaces/IQuest.sol";
import "../interfaces/IWETH.sol";
import "../utils/Math.sol";

contract Guild is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    // using SafeERC20 for IWETH;
    using Address for address;
    using Address for address payable;
    
    IWETH public constant WETH = IWETH(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    IERC20 public immutable FZM;
    IERC20 public immutable BUSD;

    // Info of each user.
    struct UserInfo {
        address user;
        // share in the quest
        uint256 share;
        uint256 deposit;
        uint256 borrow;
        // uint256 rewardDebt;
        // total yield from the quest
        uint256 shareYield;
        // current leverage
        uint8 leverage;
        // price of liquidate
        uint8 liqdPrice;
    }

    // Info of each pool.
    struct QuestInfo {
        // address of Quest contract
        address quest;
        IERC20 depositToken;
        // Reward token from LP farm
        IERC20 questToken;
        // timestamp of last compound
        uint64 lastCompoud;
        uint8 interestRate;
        uint8 liquidateFee;
        uint8 withdrawFee;
        // UserInfo[] userInfo;
    }

    // Reserve
    IGuildReserve public immutable reserve;
    
    address[] public lockedQuests;
    mapping(address => bool) public isInLockedQuests;
    mapping(address => QuestInfo) public questInfo;
    uint256 public totalQuest;

    // Info of each user that deposit to quest.
    mapping(address => mapping(address => UserInfo)) public userInfo;

    event Deposit(address indexed user, address indexed quest, uint256 amount);
    event Withdraw(address indexed user, address indexed quest, uint256 amount);
    event EmergencyWithdraw(address indexed user, address indexed quest, uint256 amount);

    // event StoreApproval(address indexed owner, address indexed quest, address indexed spender, uint256 value);
    // event StoreKeepShare(address indexed owner, address indexed quest, address indexed store, uint256 value);
    // event StoreReturnShare(address indexed user, address indexed quest, address indexed store, uint256 amount);
    // event StoreWithdraw(address indexed user, address indexed quest, address indexed store, uint256 amount);

    event AddQuest(address indexed quest);

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "Guild: EXPIRED");
        _;
    }

    constructor(
        IGuildReserve _reserve,
        IERC20 _FZM,
        IERC20 _BUSD
        // IWETH _WETH
    ) {
        reserve = _reserve;
        FZM = _FZM;
        BUSD = _BUSD;
        // WETH = _WETH;
    }

    function lockedQuestsLength() external view returns (uint256) {
        return lockedQuests.length;
    }

    function _addLocked(address quest) private {
        if (isInLockedQuests[quest]) {
            return;
        }

        isInLockedQuests[quest] = true;
        lockedQuests.push(quest);
    }

    function removeLocked(uint256 index) external {
        address quest = lockedQuests[index];
        isInLockedQuests[quest] = false;
        lockedQuests[index] = lockedQuests[lockedQuests.length - 1];
        lockedQuests.pop();
    }

    // Add a new quest to the guild.
    function add(
        address quest
    ) external onlyOwner {
        require(IQuest(quest).guild() == address(this), "?");
        require(IQuest(quest).totalSupply() >= 0, "??");
        require(questInfo[quest].quest == address(0), "duplicated");

        questInfo[quest] = QuestInfo({
            quest: quest,
            depositToken: IQuest(quest).depositToken(),
            questToken: IQuest(quest).questToken(),
            lastCompoud: uint64(block.timestamp),
            interestRate: IQuest(quest).interestRate(),
            liquidateFee: IQuest(quest).liquidateFee(),
            withdrawFee: IQuest(quest).withdrawFee()
        });
        totalQuest += 1;
        emit AddQuest(quest);
    }

    function process(address[] calldata quests) external nonReentrant {
        for (uint256 i = 0; i < quests.length; i++) {
            _deposit(msg.sender, quests[i], IERC20(address(0)), 0);
        }
    }

    function deposit(address quest, uint256 amount) external nonReentrant {
        QuestInfo storage pool = questInfo[quest];
        if (amount > 0) {
            require(_safeERC20TransferIn(pool.questToken, amount) == amount, "!amount");
        }
        _deposit(msg.sender, quest, pool.questToken, amount);
        emit Deposit(msg.sender, quest, amount);
    }

    function withdraw(address quest, uint256 shareAmount) external nonReentrant {
        QuestInfo storage pool = questInfo[quest];
        uint256 amount = _withdraw(msg.sender, quest, pool.questToken, shareAmount);
        if (amount > 0) {
            pool.questToken.safeTransfer(msg.sender, amount);
        }
        emit Withdraw(msg.sender, quest, shareAmount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(address quest) external {
        QuestInfo storage pool = questInfo[quest];
        UserInfo storage user = userInfo[quest][msg.sender];

        uint256 share = user.share;
        user.share = 0;
        user.rewardDebt = (user.storedShare * pool.questReward) / 1e12;
        if (share > 0) {
            IERC20 questToken = pool.questToken;
            uint256 questTokenBefore = questToken.balanceOf(address(this));
            IQuest(quest).withdraw(msg.sender, share);
            uint256 questTokenAfter = questToken.balanceOf(address(this));
            questToken.safeTransfer(msg.sender, questTokenAfter - questTokenBefore);
        }
        emit EmergencyWithdraw(msg.sender, quest, share);
    }

    /**
     * @dev Returns the remaining number of share that `store` will be
     * allowed to keep on behalf of `user` through {storeKeepShare}. This is
     * zero by default.
     *
     * This value changes when {approveStore} or {storeKeepShare} are called.
     */
    function storeAllowance(
        address user,
        address quest,
        address store
    ) external view returns (uint256) {
        return _storeAllowances[user][quest][store];
    }

    /**
     * @dev grant store to keep share
     */
    function approveStore(
        address quest,
        address store,
        uint256 amount
    ) external {
        _approveStore(msg.sender, quest, store, amount);
    }

    /**
     * @dev Atomically increases the allowance granted to `store` by the caller.
     */
    function increaseStoreAllowance(
        address quest,
        address store,
        uint256 addedAmount
    ) external {
        _approveStore(msg.sender, quest, store, _storeAllowances[msg.sender][quest][store] + addedAmount);
    }

    /**
     * @dev Atomically decreases the allowance granted to `store` by the caller.
     */
    function decreaseStoreAllowance(
        address quest,
        address store,
        uint256 subtractedAmount
    ) external {
        uint256 currentAllowance = _storeAllowances[msg.sender][quest][store];
        require(currentAllowance >= subtractedAmount, "decreased allowance below zero");
        unchecked {
            _approveStore(msg.sender, quest, store, currentAllowance - subtractedAmount);
        }
    }

    /**
     * @dev store pull user share to keep
     */
    function storeKeepShare(
        address _user,
        address quest,
        uint256 amount
    ) external {
        require(amount > 0, "invalid amount");
        UserInfo storage user = userInfo[quest][_user];
        user.share -= amount;
        user.storedShare += amount;
        shareStorage[_user][quest][msg.sender] += amount;

        uint256 currentAllowance = _storeAllowances[_user][quest][msg.sender];
        require(currentAllowance >= amount, "keep amount exceeds allowance");
        unchecked {
            _approveStore(_user, quest, msg.sender, currentAllowance - amount);
        }
        emit StoreKeepShare(_user, quest, msg.sender, amount);
    }

    /**
     * @dev store return share to user
     */
    function storeReturnShare(
        address _user,
        address quest,
        uint256 amount
    ) external {
        require(amount > 0, "invalid amount");
        UserInfo storage user = userInfo[quest][_user];
        shareStorage[_user][quest][msg.sender] -= amount;
        user.storedShare -= amount;
        user.share += amount;
        emit StoreReturnShare(_user, quest, msg.sender, amount);
    }
    
    /**
     * @dev low level deposit 'questToken' to quest or staking here
     *
     * 'warning' deposit amount must be guarantee by caller
     */
    function _deposit(
        address _user,
        address quest,
        uint256 amount,
        uint8 leverage
    ) private {
        QuestInfo storage pool = questInfo[quest];
        UserInfo storage user = userInfo[quest][_user];
        IERC20 depositToken = questInfo.depositToken;

        uint256 tShare = user.share + user.storedShare;
        // amount must guaranteed by caller
        if (amount > 0) {
            depositToken.safeIncreaseAllowance(quest, amount);
            uint256 addAmount = IQuest(quest).deposit(_user, amount);
            tShare += addAmount;
            user.share += addAmount;
        }
    }

    function _withdraw(
        address _user,
        address quest,
        IERC20 questToken,
        uint256 shareAmount
    ) private returns (uint256 amount) {
        QuestInfo storage pool = questInfo[quest];
        UserInfo storage user = userInfo[quest][_user];
        shareAmount = Math.min(user.share, shareAmount);

        updatePool(quest);
        uint256 tShare = user.share + user.storedShare;
        uint256 pending = ((tShare * pool.questReward) / 1e12) - user.rewardDebt;
        if (pending > 0) {
            IERC20(rewardToken).transfer(_user, pending);
        }

        tShare -= shareAmount;
        user.share -= shareAmount;
        user.rewardDebt = (tShare * pool.questReward) / 1e12;
        if (shareAmount > 0) {
            uint256 questTokenBefore = questToken.balanceOf(address(this));
            IQuest(quest).withdraw(_user, shareAmount);
            uint256 questTokenAfter = questToken.balanceOf(address(this));
            amount = questTokenAfter - questTokenBefore;
        }
    }

    function _safeERC20TransferIn(IERC20 token, uint256 amount) private returns (uint256) {
        require(amount > 0, "zero amount");

        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 balanceAfter = token.balanceOf(address(this));
        return balanceAfter - balanceBefore;
    }

    function _approveStore(
        address user,
        address quest,
        address store,
        uint256 amount
    ) private {
        require(user != address(0), "approve from the zero address");
        require(quest != address(0), "approve quest zero address");
        require(store != address(0), "approve to the zero address");

        _storeAllowances[user][quest][store] = amount;
        emit StoreApproval(user, quest, store, amount);
    }
}
