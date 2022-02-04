// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IPartyReserve.sol";
import "./interfaces/ILeader.sol";
import "../interfaces/IWETH.sol";
import "../utils/Math.sol";

contract PartyV2 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;
    using Address for address;
    using Address for address payable;

    IWETH public constant WETH = IWETH(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);

    // Info of each user.
    struct UserInfo {
        uint256 loot;
        uint256 rewardDebt;
        uint256 storedLoot;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 strategyToken;
        address leader;
        uint256 accRewardTokenPerLoot;
        uint64 allocPoint;
        uint64 lastRewardTime;
    }

    // Reserve
    IPartyReserve public immutable reserve;

    // RewardToken address
    address public immutable rewardToken;
    // RewardToken tokens rewards per second.
    uint256 public rewardTokenPerSecond;

    // Info of each pool.
    address[] public traversalPools;
    mapping(address => bool) public isInTraversalPools; // remember is leader in traversal
    mapping(address => PoolInfo) public poolInfo;
    uint256 public totalPool;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    // Info of each user that stakes to leader.
    mapping(address => mapping(address => UserInfo)) public userInfo;

    // [user] [leader] [store] => amount
    mapping(address => mapping(address => mapping(address => uint256))) private _storeAllowances;
    mapping(address => mapping(address => mapping(address => uint256))) public lootStorage;

    // Juno transportation
    address public juno;
    address public junoGuide;

    event Deposit(address indexed user, address indexed leader, uint256 amount);
    event DepositFor(address indexed user, address indexed leader, uint256 amount);
    event DepositToken(address indexed user, address indexed leader, uint256[] tokenAmount, uint256 amount);
    event DepositEther(address indexed user, address indexed leader, uint256 value, uint256 amount);
    event Withdraw(address indexed user, address indexed leader, uint256 amount);
    event WithdrawToken(address indexed user, address indexed leader, uint256 lootAmount, uint256 tokenAmount);
    event WithdrawEther(address indexed user, address indexed leader, uint256 lootAmount, uint256 value);
    event EmergencyWithdraw(address indexed user, address indexed leader, uint256 amount);

    event StoreApproval(address indexed owner, address indexed leader, address indexed spender, uint256 value);
    event StoreKeepLoot(address indexed owner, address indexed leader, address indexed store, uint256 value);
    event StoreReturnLoot(address indexed user, address indexed leader, address indexed store, uint256 amount);
    event StoreWithdraw(address indexed user, address indexed leader, address indexed store, uint256 amount);

    event AddPool(address indexed leader, uint256 allocPoint, bool withUpdate);
    event SetPool(address indexed leader, uint256 allocPoint, bool withUpdate);
    event SetRewardTokenPerSecond(uint256 rewardTokenPerSecond);
    event SetJuno(address juno);
    event SetJunoGuide(address junoGuide);

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "Party: EXPIRED");
        _;
    }

    constructor(
        IPartyReserve _reserve,
        address _rewardToken,
        uint256 _rewardTokenPerSecond,
        address _juno,
        address _junoGuide
    ) {
        reserve = _reserve;
        rewardTokenPerSecond = _rewardTokenPerSecond;
        juno = _juno;
        junoGuide = _junoGuide;
        rewardToken = _rewardToken;
    }

    function traversalPoolsLength() external view returns (uint256) {
        return traversalPools.length;
    }

    function _addTraversal(address leader) private {
        if (isInTraversalPools[leader]) {
            return;
        }

        isInTraversalPools[leader] = true;
        traversalPools.push(leader);
    }

    function removeTraversal(uint256 index) external {
        address leader = traversalPools[index];
        require(poolInfo[leader].allocPoint == 0, "allocated");

        isInTraversalPools[leader] = false;
        traversalPools[index] = traversalPools[traversalPools.length - 1];
        traversalPools.pop();
    }

    // Add a new leader to the pool.
    function add(
        address leader,
        uint64 allocPoint,
        bool withUpdate
    ) external onlyOwner {
        require(ILeader(leader).party() == address(this), "?");
        require(ILeader(leader).totalSupply() >= 0, "??");
        require(poolInfo[leader].leader == address(0), "duplicated");
        if (withUpdate) {
            massUpdatePools();
        }

        poolInfo[leader] = PoolInfo({
            strategyToken: ILeader(leader).strategyToken(),
            leader: leader,
            allocPoint: allocPoint,
            lastRewardTime: uint64(block.timestamp),
            accRewardTokenPerLoot: 0
        });
        totalPool += 1;
        totalAllocPoint += allocPoint;
        if (allocPoint > 0) {
            _addTraversal(leader);
        }
        emit AddPool(leader, allocPoint, withUpdate);
    }

    // Update the given pool's RewardToken allocation point.
    function set(
        address leader,
        uint64 allocPoint,
        bool withUpdate
    ) external onlyOwner {
        require(leader != address(0), "invalid leader");
        PoolInfo storage pool = poolInfo[leader];
        require(pool.leader == leader, "!found");
        if (withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = (totalAllocPoint - pool.allocPoint) + allocPoint;
        pool.allocPoint = allocPoint;
        if (allocPoint > 0) {
            _addTraversal(leader);
        }
        emit SetPool(leader, allocPoint, withUpdate);
    }

    /**
     * @dev View function to see pending RewardTokens on frontend.
     *
     */
    function pendingRewardToken(address leader, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[leader];
        UserInfo storage user = userInfo[leader][_user];
        uint256 accRewardTokenPerLoot = pool.accRewardTokenPerLoot;
        uint256 leaderSupply = ILeader(leader).totalSupply();
        if (block.timestamp > pool.lastRewardTime && leaderSupply != 0) {
            uint256 time = block.timestamp - pool.lastRewardTime;
            uint256 rewardTokenReward = (time * rewardTokenPerSecond * pool.allocPoint) / totalAllocPoint;

            uint256 stakingBal = reserve.balances();
            accRewardTokenPerLoot += (Math.min(rewardTokenReward, stakingBal) * 1e12) / leaderSupply;
        }

        uint256 tLoot = user.loot + user.storedLoot;
        uint256 r = ((tLoot * accRewardTokenPerLoot) / 1e12) - user.rewardDebt;
        return r;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        for (uint256 i = 0; i < traversalPools.length; i++) {
            updatePool(traversalPools[i]);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(address leader) public {
        PoolInfo storage pool = poolInfo[leader];
        require(pool.leader == leader, "!pool");
        if (block.timestamp > pool.lastRewardTime) {
            uint256 leaderSupply = ILeader(leader).totalSupply();
            if (leaderSupply > 0) {
                uint256 time = block.timestamp - pool.lastRewardTime;
                uint256 rewardTokenReward = (time * rewardTokenPerSecond * pool.allocPoint) / totalAllocPoint;
                uint256 r = reserve.withdraw(address(this), rewardTokenReward);
                pool.accRewardTokenPerLoot += (r * 1e12) / leaderSupply;
            }
            pool.lastRewardTime = uint64(block.timestamp);
        }
    }

    /**
     * @dev low level deposit 'strategyToken' to leader or staking here
     *
     * 'warning' deposit amount must be guarantee by caller
     */
    function _deposit(
        address _user,
        address leader,
        IERC20 strategyToken,
        uint256 amount
    ) private {
        PoolInfo storage pool = poolInfo[leader];
        UserInfo storage user = userInfo[leader][_user];

        updatePool(leader);
        uint256 tLoot = user.loot + user.storedLoot;
        if (tLoot > 0) {
            uint256 pending = ((tLoot * pool.accRewardTokenPerLoot) / 1e12) - user.rewardDebt;
            if (pending > 0) {
                IERC20(rewardToken).transfer(_user, pending);
            }
        }

        // amount must guaranteed by caller
        if (amount > 0) {
            strategyToken.safeIncreaseAllowance(leader, amount);
            uint256 addAmount = ILeader(leader).deposit(_user, amount);
            tLoot += addAmount;
            user.loot += addAmount;
        }
        user.rewardDebt = (tLoot * pool.accRewardTokenPerLoot) / 1e12;
    }

    function harvest(address[] calldata leaders) external nonReentrant {
        for (uint256 i = 0; i < leaders.length; i++) {
            _deposit(msg.sender, leaders[i], IERC20(address(0)), 0);
        }
    }

    function deposit(address leader, uint256 amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[leader];
        if (amount > 0) {
            require(_safeERC20TransferIn(pool.strategyToken, amount) == amount, "!amount");
        }
        _deposit(msg.sender, leader, pool.strategyToken, amount);
        emit Deposit(msg.sender, leader, amount);
    }

    function depositFor(
        address user,
        address leader,
        uint256 amount
    ) external nonReentrant {
        PoolInfo storage pool = poolInfo[leader];
        if (amount > 0) {
            require(_safeERC20TransferIn(pool.strategyToken, amount) == amount, "!amount");
        }
        _deposit(user, leader, pool.strategyToken, amount);
        emit DepositFor(user, leader, amount);
    }

    function depositToken(
        address leader,
        IERC20[] calldata tokens,
        uint256[] calldata tokenAmounts,
        uint256 amountOutMin,
        uint256 deadline,
        bytes calldata data
    ) external nonReentrant ensure(deadline) {
        require(tokens.length == tokenAmounts.length, "length mismatch");
        PoolInfo storage pool = poolInfo[leader];
        IERC20 strategyToken = pool.strategyToken;

        uint256 beforeBal = strategyToken.balanceOf(address(this));
        for (uint256 i = 0; i < tokens.length; i++) {
            require(_safeERC20TransferIn(tokens[i], tokenAmounts[i]) == tokenAmounts[i], "!amount");
            if (tokens[i] != strategyToken) {
                tokens[i].safeTransfer(juno, tokenAmounts[i]);
            }
        }
        juno.functionCall(data, "juno: failed");
        uint256 amount = strategyToken.balanceOf(address(this)) - beforeBal;
        require(amount >= amountOutMin, "insufficient output amount");

        _deposit(msg.sender, leader, strategyToken, amount);
        emit DepositToken(msg.sender, leader, tokenAmounts, amount);
    }

    function depositEther(
        address leader,
        uint256 amountOutMin,
        uint256 deadline,
        bytes calldata data
    ) external payable nonReentrant ensure(deadline) {
        require(msg.value > 0, "!value");
        PoolInfo storage pool = poolInfo[leader];
        IERC20 strategyToken = pool.strategyToken;

        uint256 beforeBal = strategyToken.balanceOf(address(this));
        {
            WETH.deposit{value: msg.value}();
            WETH.safeTransfer(juno, msg.value);
            juno.functionCall(data, "juno: failed");
        }
        uint256 afterBal = strategyToken.balanceOf(address(this));
        uint256 amount = afterBal - beforeBal;
        require(amount >= amountOutMin, "insufficient output amount");

        _deposit(msg.sender, leader, strategyToken, amount);
        emit DepositEther(msg.sender, leader, msg.value, amount);
    }

    function _withdraw(
        address _user,
        address leader,
        IERC20 strategyToken,
        uint256 lootAmount
    ) private returns (uint256 amount) {
        PoolInfo storage pool = poolInfo[leader];
        UserInfo storage user = userInfo[leader][_user];
        lootAmount = Math.min(user.loot, lootAmount);

        updatePool(leader);
        uint256 tLoot = user.loot + user.storedLoot;
        uint256 pending = ((tLoot * pool.accRewardTokenPerLoot) / 1e12) - user.rewardDebt;
        if (pending > 0) {
            IERC20(rewardToken).transfer(_user, pending);
        }

        tLoot -= lootAmount;
        user.loot -= lootAmount;
        user.rewardDebt = (tLoot * pool.accRewardTokenPerLoot) / 1e12;
        if (lootAmount > 0) {
            uint256 strategyTokenBefore = strategyToken.balanceOf(address(this));
            ILeader(leader).withdraw(_user, lootAmount);
            uint256 strategyTokenAfter = strategyToken.balanceOf(address(this));
            amount = strategyTokenAfter - strategyTokenBefore;
        }
    }

    function withdraw(address leader, uint256 lootAmount) external nonReentrant {
        PoolInfo storage pool = poolInfo[leader];
        uint256 amount = _withdraw(msg.sender, leader, pool.strategyToken, lootAmount);
        if (amount > 0) {
            pool.strategyToken.safeTransfer(msg.sender, amount);
        }
        emit Withdraw(msg.sender, leader, lootAmount);
    }

    // withdraw from allowed store. send pending reward to owner but transfer strategyToken to store and let store handle the rest
    function storeWithdraw(
        address _user,
        address leader,
        uint256 lootAmount
    ) external nonReentrant {
        require(lootAmount > 0, "invalid amount");
        PoolInfo storage pool = poolInfo[leader];
        UserInfo storage user = userInfo[leader][_user];
        lootStorage[_user][leader][msg.sender] -= lootAmount;
        user.storedLoot -= lootAmount;
        user.loot += lootAmount;

        uint256 amount = _withdraw(_user, leader, pool.strategyToken, lootAmount);
        if (amount > 0) {
            pool.strategyToken.safeTransfer(msg.sender, amount);
        }
        emit StoreWithdraw(_user, leader, msg.sender, amount);
    }

    function withdrawToken(
        address leader,
        IERC20 token,
        uint256 lootAmount,
        uint256 amountOutMin,
        uint256 deadline,
        bytes calldata data
    ) external nonReentrant ensure(deadline) {
        PoolInfo storage pool = poolInfo[leader];
        IERC20 strategyToken = pool.strategyToken;
        require(token != strategyToken, "!strategyToken");
        uint256 amount = _withdraw(msg.sender, leader, strategyToken, lootAmount);

        uint256 beforeBal = token.balanceOf(address(this));
        {
            strategyToken.safeTransfer(juno, amount);
            juno.functionCall(data, "juno: failed");
        }
        uint256 afterBal = token.balanceOf(address(this));
        uint256 amountOut = afterBal - beforeBal;
        require(amountOut >= amountOutMin, "insufficient output amount");

        token.safeTransfer(msg.sender, amountOut);
        emit WithdrawToken(msg.sender, leader, lootAmount, amountOut);
    }

    function withdrawEther(
        address leader,
        uint256 lootAmount,
        uint256 amountOutMin,
        uint256 deadline,
        bytes calldata data
    ) external nonReentrant ensure(deadline) {
        PoolInfo storage pool = poolInfo[leader];
        uint256 amount = _withdraw(msg.sender, leader, pool.strategyToken, lootAmount);

        uint256 beforeBal = WETH.balanceOf(address(this));
        {
            pool.strategyToken.safeTransfer(juno, amount);
            juno.functionCall(data, "juno: failed");
        }
        uint256 afterBal = WETH.balanceOf(address(this));
        uint256 amountOut = afterBal - beforeBal;
        require(amountOut >= amountOutMin, "insufficient output amount");

        WETH.withdraw(amountOut);
        payable(msg.sender).sendValue(amountOut);
        emit WithdrawEther(msg.sender, leader, lootAmount, amountOut);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(address leader) external {
        PoolInfo storage pool = poolInfo[leader];
        UserInfo storage user = userInfo[leader][msg.sender];

        uint256 loot = user.loot;
        user.loot = 0;
        user.rewardDebt = (user.storedLoot * pool.accRewardTokenPerLoot) / 1e12;
        if (loot > 0) {
            IERC20 strategyToken = pool.strategyToken;
            uint256 strategyTokenBefore = strategyToken.balanceOf(address(this));
            ILeader(leader).withdraw(msg.sender, loot);
            uint256 strategyTokenAfter = strategyToken.balanceOf(address(this));
            strategyToken.safeTransfer(msg.sender, strategyTokenAfter - strategyTokenBefore);
        }
        emit EmergencyWithdraw(msg.sender, leader, loot);
    }

    /**
     * @dev Returns the remaining number of loot that `store` will be
     * allowed to keep on behalf of `user` through {storeKeepLoot}. This is
     * zero by default.
     *
     * This value changes when {approveStore} or {storeKeepLoot} are called.
     */
    function storeAllowance(
        address user,
        address leader,
        address store
    ) external view returns (uint256) {
        return _storeAllowances[user][leader][store];
    }

    function _approveStore(
        address user,
        address leader,
        address store,
        uint256 amount
    ) private {
        require(user != address(0), "approve from the zero address");
        require(leader != address(0), "approve leader zero address");
        require(store != address(0), "approve to the zero address");

        _storeAllowances[user][leader][store] = amount;
        emit StoreApproval(user, leader, store, amount);
    }

    /**
     * @dev grant store to keep loot
     */
    function approveStore(
        address leader,
        address store,
        uint256 amount
    ) external {
        _approveStore(msg.sender, leader, store, amount);
    }

    /**
     * @dev Atomically increases the allowance granted to `store` by the caller.
     */
    function increaseStoreAllowance(
        address leader,
        address store,
        uint256 addedAmount
    ) external {
        _approveStore(msg.sender, leader, store, _storeAllowances[msg.sender][leader][store] + addedAmount);
    }

    /**
     * @dev Atomically decreases the allowance granted to `store` by the caller.
     */
    function decreaseStoreAllowance(
        address leader,
        address store,
        uint256 subtractedAmount
    ) external {
        uint256 currentAllowance = _storeAllowances[msg.sender][leader][store];
        require(currentAllowance >= subtractedAmount, "decreased allowance below zero");
        unchecked {
            _approveStore(msg.sender, leader, store, currentAllowance - subtractedAmount);
        }
    }

    /**
     * @dev store pull user loot to keep
     */
    function storeKeepLoot(
        address _user,
        address leader,
        uint256 amount
    ) external {
        require(amount > 0, "invalid amount");
        UserInfo storage user = userInfo[leader][_user];
        user.loot -= amount;
        user.storedLoot += amount;
        lootStorage[_user][leader][msg.sender] += amount;

        uint256 currentAllowance = _storeAllowances[_user][leader][msg.sender];
        require(currentAllowance >= amount, "keep amount exceeds allowance");
        unchecked {
            _approveStore(_user, leader, msg.sender, currentAllowance - amount);
        }
        emit StoreKeepLoot(_user, leader, msg.sender, amount);
    }

    /**
     * @dev store return loot to user
     */
    function storeReturnLoot(
        address _user,
        address leader,
        uint256 amount
    ) external {
        require(amount > 0, "invalid amount");
        UserInfo storage user = userInfo[leader][_user];
        lootStorage[_user][leader][msg.sender] -= amount;
        user.storedLoot -= amount;
        user.loot += amount;
        emit StoreReturnLoot(_user, leader, msg.sender, amount);
    }

    function setRewardTokenPerSecond(uint256 _rewardTokenPerSecond) external onlyOwner {
        massUpdatePools();
        rewardTokenPerSecond = _rewardTokenPerSecond;
        emit SetRewardTokenPerSecond(_rewardTokenPerSecond);
    }

    function setJuno(address _juno) external {
        require(msg.sender == junoGuide, "!guide");
        juno = _juno;
        emit SetJuno(_juno);
    }

    function setJunoGuide(address _junoGuide) external onlyOwner {
        junoGuide = _junoGuide;
        emit SetJunoGuide(_junoGuide);
    }

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
