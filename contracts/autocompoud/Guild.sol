// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IGuildReserve.sol";
import "./interfaces/IParty.sol";
import "../interfaces/IWETH.sol";
import "../utils/Math.sol";

contract Guild is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    // using SafeERC20 for IWETH;
    using Address for address;
    using Address for address payable;
    
    IWETH public immutable WETH; // = IWETH(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    IERC20 public immutable FZM;

    // Info of each user.
    struct UserInfo {
        // share in the quest
        uint256 share;
        uint256 deposit;
        uint256 borrow;
        // uint256 rewardDebt;
        // total yield from the quest
        uint256 shareYield;
    }

    // Info of each pool.
    struct QuestInfo {
        // Reward token from LP farm
        IERC20 questToken;
        // address of Quest contract
        address quest;
        // Current un-compound reward
        uint256 questReward;
        // uint64 allocPoint;
        // timestamp of last compound
        uint64 lastCompoud;
        uint64 interestRate;
        uint64 perfFee;
        uint64 liquidateFee;
    }

    // Reserve
    IGuildReserve public immutable reserve;

    // // RewardToken address
    // address public immutable rewardToken;
    // // RewardToken tokens rewards per second.
    // uint256 public rewardTokenPerSecond;

    // Info of each pool.
    // address[] public traversalPools;
    // mapping(address => bool) public isInTraversalPools; // remember is party in traversal
    mapping(address => QuestInfo) public questInfo;
    uint256 public totalPool;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    // uint256 public totalAllocPoint;

    // Info of each user that stakes to party.
    mapping(address => mapping(address => UserInfo)) public userInfo;

    // [user] [quest] [store] => amount
    mapping(address => mapping(address => mapping(address => uint256))) private _storeAllowances;
    mapping(address => mapping(address => mapping(address => uint256))) public shareStorage;

    // Juno transportation
    // address public juno;
    // address public junoGuide;

    event Deposit(address indexed user, address indexed party, uint256 amount);
    event DepositFor(address indexed user, address indexed party, uint256 amount);
    event DepositToken(address indexed user, address indexed party, uint256[] tokenAmount, uint256 amount);
    event DepositEther(address indexed user, address indexed party, uint256 value, uint256 amount);
    event Withdraw(address indexed user, address indexed party, uint256 amount);
    event WithdrawToken(address indexed user, address indexed party, uint256 shareAmount, uint256 tokenAmount);
    event WithdrawEther(address indexed user, address indexed party, uint256 shareAmount, uint256 value);
    event EmergencyWithdraw(address indexed user, address indexed party, uint256 amount);

    event StoreApproval(address indexed owner, address indexed party, address indexed spender, uint256 value);
    event StoreKeepShare(address indexed owner, address indexed party, address indexed store, uint256 value);
    event StoreReturnShare(address indexed user, address indexed party, address indexed store, uint256 amount);
    event StoreWithdraw(address indexed user, address indexed party, address indexed store, uint256 amount);

    event AddPool(address indexed party, uint256 allocPoint, bool withUpdate);
    event SetPool(address indexed party, uint256 allocPoint, bool withUpdate);
    // event SetRewardTokenPerSecond(uint256 rewardTokenPerSecond);
    // event SetJuno(address juno);
    // event SetJunoGuide(address junoGuide);

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "Guild: EXPIRED");
        _;
    }

    constructor(
        IGuildReserve _reserve,
        IERC20 _FZM,
        IWETH _WETH
        // address _rewardToken,
        // uint256 _rewardTokenPerSecond,
        // address _juno,
        // address _junoGuide
    ) {
        reserve = _reserve;
        FZM = _FZM;
        WETH = _WETH;
        // rewardTokenPerSecond = _rewardTokenPerSecond;
        // juno = _juno;
        // junoGuide = _junoGuide;
        // rewardToken = _rewardToken;
    }

    function traversalPoolsLength() external view returns (uint256) {
        return traversalPools.length;
    }

    function _addTraversal(address party) private {
        if (isInTraversalPools[party]) {
            return;
        }

        isInTraversalPools[party] = true;
        traversalPools.push(party);
    }

    function removeTraversal(uint256 index) external {
        address party = traversalPools[index];
        require(questInfo[party].allocPoint == 0, "allocated");

        isInTraversalPools[party] = false;
        traversalPools[index] = traversalPools[traversalPools.length - 1];
        traversalPools.pop();
    }

    // Add a new party to the pool.
    function add(
        address party,
        // uint64 allocPoint,
        bool withUpdate
    ) external onlyOwner {
        require(IParty(party).guild() == address(this), "?");
        require(IParty(party).totalSupply() >= 0, "??");
        require(questInfo[party].party == address(0), "duplicated");
        if (withUpdate) {
            massUpdatePools();
        }

        questInfo[party] = QuestInfo({
            questToken: IParty(party).questToken(),
            party: party,
            // allocPoint: allocPoint,
            lastCompoud: uint64(block.timestamp),
            questReward: 0
        });
        totalPool += 1;
        totalAllocPoint += allocPoint;
        if (allocPoint > 0) {
            _addTraversal(party);
        }
        emit AddPool(party, allocPoint, withUpdate);
    }

    // Update the given pool's RewardToken allocation point.
    function set(
        address party,
        uint64 allocPoint,
        bool withUpdate
    ) external onlyOwner {
        require(party != address(0), "invalid party");
        QuestInfo storage pool = questInfo[party];
        require(pool.party == party, "!found");
        if (withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = (totalAllocPoint - pool.allocPoint) + allocPoint;
        pool.allocPoint = allocPoint;
        if (allocPoint > 0) {
            _addTraversal(party);
        }
        emit SetPool(party, allocPoint, withUpdate);
    }

    /**
     * @dev View function to see pending RewardTokens on frontend.
     *
     */
    function pendingRewardToken(address party, address _user) external view returns (uint256) {
        QuestInfo storage pool = questInfo[party];
        UserInfo storage user = userInfo[party][_user];
        uint256 questReward = pool.questReward;
        uint256 partySupply = IParty(party).totalSupply();
        if (block.timestamp > pool.lastCompoud && partySupply != 0) {
            uint256 time = block.timestamp - pool.lastCompoud;
            uint256 rewardTokenReward = (time * rewardTokenPerSecond * pool.allocPoint) / totalAllocPoint;

            uint256 stakingBal = reserve.balances();
            questReward += (Math.min(rewardTokenReward, stakingBal) * 1e12) / partySupply;
        }

        uint256 tShare = user.share + user.storedShare;
        uint256 r = ((tShare * questReward) / 1e12) - user.rewardDebt;
        return r;
    }

    Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        for (uint256 i = 0; i < traversalPools.length; i++) {
            updatePool(traversalPools[i]);
        }
    }

    Update reward variables of the given pool to be up-to-date.
    function updatePool(address party) public {
        QuestInfo storage pool = questInfo[party];
        require(pool.party == party, "!pool");
        if (block.timestamp > pool.lastCompoud) {
            uint256 partySupply = IParty(party).totalSupply();
            if (partySupply > 0) {
                uint256 time = block.timestamp - pool.lastCompoud;
                uint256 rewardTokenReward = (time * rewardTokenPerSecond * pool.allocPoint) / totalAllocPoint;
                uint256 r = reserve.withdraw(address(this), rewardTokenReward);
                pool.questReward += (r * 1e12) / partySupply;
            }
            pool.lastCompoud = uint64(block.timestamp);
        }
    }

    /**
     * @dev low level deposit 'questToken' to party or staking here
     *
     * 'warning' deposit amount must be guarantee by caller
     */
    function _deposit(
        address _user,
        address party,
        IERC20 questToken,
        uint256 amount
    ) private {
        QuestInfo storage pool = questInfo[party];
        UserInfo storage user = userInfo[party][_user];

        // updatePool(party);
        uint256 tShare = user.share + user.storedShare;
        // if (tShare > 0) {
        //     uint256 pending = ((tShare * pool.questReward) / 1e12) - user.rewardDebt;
        //     if (pending > 0) {
        //         IERC20(rewardToken).transfer(_user, pending);
        //     }
        // }

        // amount must guaranteed by caller
        if (amount > 0) {
            questToken.safeIncreaseAllowance(party, amount);
            uint256 addAmount = IParty(party).deposit(_user, amount);
            tShare += addAmount;
            user.share += addAmount;
        }
        // user.rewardDebt = (tShare * pool.questReward) / 1e12;
    }

    function harvest(address[] calldata partys) external nonReentrant {
        for (uint256 i = 0; i < partys.length; i++) {
            _deposit(msg.sender, partys[i], IERC20(address(0)), 0);
        }
    }

    function deposit(address party, uint256 amount) external nonReentrant {
        QuestInfo storage pool = questInfo[party];
        if (amount > 0) {
            require(_safeERC20TransferIn(pool.questToken, amount) == amount, "!amount");
        }
        _deposit(msg.sender, party, pool.questToken, amount);
        emit Deposit(msg.sender, party, amount);
    }

    function depositFor(
        address user,
        address party,
        uint256 amount
    ) external nonReentrant {
        QuestInfo storage pool = questInfo[party];
        if (amount > 0) {
            require(_safeERC20TransferIn(pool.questToken, amount) == amount, "!amount");
        }
        _deposit(user, party, pool.questToken, amount);
        emit DepositFor(user, party, amount);
    }

    function depositToken(
        address party,
        IERC20[] calldata tokens,
        uint256[] calldata tokenAmounts,
        uint256 amountOutMin,
        uint256 deadline,
        bytes calldata data
    ) external nonReentrant ensure(deadline) {
        require(tokens.length == tokenAmounts.length, "length mismatch");
        QuestInfo storage pool = questInfo[party];
        IERC20 questToken = pool.questToken;

        uint256 beforeBal = questToken.balanceOf(address(this));
        for (uint256 i = 0; i < tokens.length; i++) {
            require(_safeERC20TransferIn(tokens[i], tokenAmounts[i]) == tokenAmounts[i], "!amount");
            if (tokens[i] != questToken) {
                tokens[i].safeTransfer(juno, tokenAmounts[i]);
            }
        }
        juno.functionCall(data, "juno: failed");
        uint256 amount = questToken.balanceOf(address(this)) - beforeBal;
        require(amount >= amountOutMin, "insufficient output amount");

        _deposit(msg.sender, party, questToken, amount);
        emit DepositToken(msg.sender, party, tokenAmounts, amount);
    }

    // function depositEther(
    //     address party,
    //     uint256 amountOutMin,
    //     uint256 deadline,
    //     bytes calldata data
    // ) external payable nonReentrant ensure(deadline) {
    //     require(msg.value > 0, "!value");
    //     QuestInfo storage pool = questInfo[party];
    //     IERC20 questToken = pool.questToken;

    //     uint256 beforeBal = questToken.balanceOf(address(this));
    //     {
    //         WETH.deposit{value: msg.value}();
    //         WETH.safeTransfer(juno, msg.value);
    //         juno.functionCall(data, "juno: failed");
    //     }
    //     uint256 afterBal = questToken.balanceOf(address(this));
    //     uint256 amount = afterBal - beforeBal;
    //     require(amount >= amountOutMin, "insufficient output amount");

    //     _deposit(msg.sender, party, questToken, amount);
    //     emit DepositEther(msg.sender, party, msg.value, amount);
    // }

    function _withdraw(
        address _user,
        address party,
        IERC20 questToken,
        uint256 shareAmount
    ) private returns (uint256 amount) {
        QuestInfo storage pool = questInfo[party];
        UserInfo storage user = userInfo[party][_user];
        shareAmount = Math.min(user.share, shareAmount);

        updatePool(party);
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
            IParty(party).withdraw(_user, shareAmount);
            uint256 questTokenAfter = questToken.balanceOf(address(this));
            amount = questTokenAfter - questTokenBefore;
        }
    }

    function withdraw(address party, uint256 shareAmount) external nonReentrant {
        QuestInfo storage pool = questInfo[party];
        uint256 amount = _withdraw(msg.sender, party, pool.questToken, shareAmount);
        if (amount > 0) {
            pool.questToken.safeTransfer(msg.sender, amount);
        }
        emit Withdraw(msg.sender, party, shareAmount);
    }

    // withdraw from allowed store. send pending reward to owner but transfer questToken to store and let store handle the rest
    function storeWithdraw(
        address _user,
        address party,
        uint256 shareAmount
    ) external nonReentrant {
        require(shareAmount > 0, "invalid amount");
        QuestInfo storage pool = questInfo[party];
        UserInfo storage user = userInfo[party][_user];
        shareStorage[_user][party][msg.sender] -= shareAmount;
        user.storedShare -= shareAmount;
        user.share += shareAmount;

        uint256 amount = _withdraw(_user, party, pool.questToken, shareAmount);
        if (amount > 0) {
            pool.questToken.safeTransfer(msg.sender, amount);
        }
        emit StoreWithdraw(_user, party, msg.sender, amount);
    }

    function withdrawToken(
        address party,
        IERC20 token,
        uint256 shareAmount,
        uint256 amountOutMin,
        uint256 deadline,
        bytes calldata data
    ) external nonReentrant ensure(deadline) {
        QuestInfo storage pool = questInfo[party];
        IERC20 questToken = pool.questToken;
        require(token != questToken, "!questToken");
        uint256 amount = _withdraw(msg.sender, party, questToken, shareAmount);

        uint256 beforeBal = token.balanceOf(address(this));
        {
            questToken.safeTransfer(juno, amount);
            juno.functionCall(data, "juno: failed");
        }
        uint256 afterBal = token.balanceOf(address(this));
        uint256 amountOut = afterBal - beforeBal;
        require(amountOut >= amountOutMin, "insufficient output amount");

        token.safeTransfer(msg.sender, amountOut);
        emit WithdrawToken(msg.sender, party, shareAmount, amountOut);
    }

    function withdrawEther(
        address party,
        uint256 shareAmount,
        uint256 amountOutMin,
        uint256 deadline,
        bytes calldata data
    ) external nonReentrant ensure(deadline) {
        QuestInfo storage pool = questInfo[party];
        uint256 amount = _withdraw(msg.sender, party, pool.questToken, shareAmount);

        uint256 beforeBal = WETH.balanceOf(address(this));
        {
            pool.questToken.safeTransfer(juno, amount);
            juno.functionCall(data, "juno: failed");
        }
        uint256 afterBal = WETH.balanceOf(address(this));
        uint256 amountOut = afterBal - beforeBal;
        require(amountOut >= amountOutMin, "insufficient output amount");

        WETH.withdraw(amountOut);
        payable(msg.sender).sendValue(amountOut);
        emit WithdrawEther(msg.sender, party, shareAmount, amountOut);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(address party) external {
        QuestInfo storage pool = questInfo[party];
        UserInfo storage user = userInfo[party][msg.sender];

        uint256 share = user.share;
        user.share = 0;
        user.rewardDebt = (user.storedShare * pool.questReward) / 1e12;
        if (share > 0) {
            IERC20 questToken = pool.questToken;
            uint256 questTokenBefore = questToken.balanceOf(address(this));
            IParty(party).withdraw(msg.sender, share);
            uint256 questTokenAfter = questToken.balanceOf(address(this));
            questToken.safeTransfer(msg.sender, questTokenAfter - questTokenBefore);
        }
        emit EmergencyWithdraw(msg.sender, party, share);
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
        address party,
        address store
    ) external view returns (uint256) {
        return _storeAllowances[user][party][store];
    }

    function _approveStore(
        address user,
        address party,
        address store,
        uint256 amount
    ) private {
        require(user != address(0), "approve from the zero address");
        require(party != address(0), "approve party zero address");
        require(store != address(0), "approve to the zero address");

        _storeAllowances[user][party][store] = amount;
        emit StoreApproval(user, party, store, amount);
    }

    /**
     * @dev grant store to keep share
     */
    function approveStore(
        address party,
        address store,
        uint256 amount
    ) external {
        _approveStore(msg.sender, party, store, amount);
    }

    /**
     * @dev Atomically increases the allowance granted to `store` by the caller.
     */
    function increaseStoreAllowance(
        address party,
        address store,
        uint256 addedAmount
    ) external {
        _approveStore(msg.sender, party, store, _storeAllowances[msg.sender][party][store] + addedAmount);
    }

    /**
     * @dev Atomically decreases the allowance granted to `store` by the caller.
     */
    function decreaseStoreAllowance(
        address party,
        address store,
        uint256 subtractedAmount
    ) external {
        uint256 currentAllowance = _storeAllowances[msg.sender][party][store];
        require(currentAllowance >= subtractedAmount, "decreased allowance below zero");
        unchecked {
            _approveStore(msg.sender, party, store, currentAllowance - subtractedAmount);
        }
    }

    /**
     * @dev store pull user share to keep
     */
    function storeKeepShare(
        address _user,
        address party,
        uint256 amount
    ) external {
        require(amount > 0, "invalid amount");
        UserInfo storage user = userInfo[party][_user];
        user.share -= amount;
        user.storedShare += amount;
        shareStorage[_user][party][msg.sender] += amount;

        uint256 currentAllowance = _storeAllowances[_user][party][msg.sender];
        require(currentAllowance >= amount, "keep amount exceeds allowance");
        unchecked {
            _approveStore(_user, party, msg.sender, currentAllowance - amount);
        }
        emit StoreKeepShare(_user, party, msg.sender, amount);
    }

    /**
     * @dev store return share to user
     */
    function storeReturnShare(
        address _user,
        address party,
        uint256 amount
    ) external {
        require(amount > 0, "invalid amount");
        UserInfo storage user = userInfo[party][_user];
        shareStorage[_user][party][msg.sender] -= amount;
        user.storedShare -= amount;
        user.share += amount;
        emit StoreReturnShare(_user, party, msg.sender, amount);
    }

    // function setRewardTokenPerSecond(uint256 _rewardTokenPerSecond) external onlyOwner {
    //     massUpdatePools();
    //     rewardTokenPerSecond = _rewardTokenPerSecond;
    //     emit SetRewardTokenPerSecond(_rewardTokenPerSecond);
    // }

    // function setJuno(address _juno) external {
    //     require(msg.sender == junoGuide, "!guide");
    //     juno = _juno;
    //     emit SetJuno(_juno);
    // }

    // function setJunoGuide(address _junoGuide) external onlyOwner {
    //     junoGuide = _junoGuide;
    //     emit SetJunoGuide(_junoGuide);
    // }

    function _safeERC20TransferIn(IERC20 token, uint256 amount) private returns (uint256) {
        require(amount > 0, "zero amount");

        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 balanceAfter = token.balanceOf(address(this));
        return balanceAfter - balanceBefore;
    }

    receive() external payable {
        require(msg.sender == address(WETH), "reject");
    }
}
