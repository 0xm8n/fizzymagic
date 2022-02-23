//SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IPronteraReserve.sol";
import "./interfaces/IIzludeV2.sol";
import "./interfaces/IWETH.sol";
import "../utils/Math.sol";

contract PronteraV2 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;
    using Address for address;
    using Address for address payable;

    IWETH public constant WETH = IWETH(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);

    // Info of each user.
    struct UserInfo {
        uint256 jellopy;
        uint256 rewardDebt;
        uint256 storedJellopy;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 want;
        address izlude;
        uint256 accKSWPerJellopy;
        uint64 allocPoint;
        uint64 lastRewardTime;
    }

    // Reserve
    IPronteraReserve public immutable reserve;

    // KSW address
    address public immutable ksw;
    // KSW tokens rewards per second.
    uint256 public kswPerSecond;

    // Info of each pool.
    address[] public traversalPools;
    mapping(address => bool) public isInTraversalPools; // remember is izlude in traversal
    mapping(address => PoolInfo) public poolInfo;
    uint256 public totalPool;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    // Info of each user that stakes to izlude.
    mapping(address => mapping(address => UserInfo)) public userInfo;

    // [user] [izlude] [store] => amount
    mapping(address => mapping(address => mapping(address => uint256))) private _storeAllowances;
    mapping(address => mapping(address => mapping(address => uint256))) public jellopyStorage;

    // Juno transportation
    address public juno;
    address public junoGuide;

    event Deposit(address indexed user, address indexed izlude, uint256 amount);
    event DepositFor(address indexed user, address indexed izlude, uint256 amount);
    event DepositToken(address indexed user, address indexed izlude, uint256[] tokenAmount, uint256 amount);
    event DepositEther(address indexed user, address indexed izlude, uint256 value, uint256 amount);
    event Withdraw(address indexed user, address indexed izlude, uint256 amount);
    event WithdrawToken(address indexed user, address indexed izlude, uint256 jellopyAmount, uint256 tokenAmount);
    event WithdrawEther(address indexed user, address indexed izlude, uint256 jellopyAmount, uint256 value);
    event EmergencyWithdraw(address indexed user, address indexed izlude, uint256 amount);

    event StoreApproval(address indexed owner, address indexed izlude, address indexed spender, uint256 value);
    event StoreKeepJellopy(address indexed owner, address indexed izlude, address indexed store, uint256 value);
    event StoreReturnJellopy(address indexed user, address indexed izlude, address indexed store, uint256 amount);
    event StoreWithdraw(address indexed user, address indexed izlude, address indexed store, uint256 amount);

    event AddPool(address indexed izlude, uint256 allocPoint, bool withUpdate);
    event SetPool(address indexed izlude, uint256 allocPoint, bool withUpdate);
    event SetKSWPerSecond(uint256 kswPerSecond);
    event SetJuno(address juno);
    event SetJunoGuide(address junoGuide);

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "Prontera: EXPIRED");
        _;
    }

    constructor(
        IPronteraReserve _reserve,
        address _ksw,
        uint256 _kswPerSecond,
        address _juno,
        address _junoGuide
    ) {
        reserve = _reserve;
        kswPerSecond = _kswPerSecond;
        juno = _juno;
        junoGuide = _junoGuide;
        ksw = _ksw;
    }

    function traversalPoolsLength() external view returns (uint256) {
        return traversalPools.length;
    }

    function _addTraversal(address izlude) private {
        if (isInTraversalPools[izlude]) {
            return;
        }

        isInTraversalPools[izlude] = true;
        traversalPools.push(izlude);
    }

    function removeTraversal(uint256 index) external {
        address izlude = traversalPools[index];
        require(poolInfo[izlude].allocPoint == 0, "allocated");

        isInTraversalPools[izlude] = false;
        traversalPools[index] = traversalPools[traversalPools.length - 1];
        traversalPools.pop();
    }

    // Add a new izlude to the pool.
    function add(
        address izlude,
        uint64 allocPoint,
        bool withUpdate
    ) external onlyOwner {
        require(IIzludeV2(izlude).prontera() == address(this), "?");
        require(IIzludeV2(izlude).totalSupply() >= 0, "??");
        require(poolInfo[izlude].izlude == address(0), "duplicated");
        if (withUpdate) {
            massUpdatePools();
        }

        poolInfo[izlude] = PoolInfo({
            want: IIzludeV2(izlude).want(),
            izlude: izlude,
            allocPoint: allocPoint,
            lastRewardTime: uint64(block.timestamp),
            accKSWPerJellopy: 0
        });
        totalPool += 1;
        totalAllocPoint += allocPoint;
        if (allocPoint > 0) {
            _addTraversal(izlude);
        }
        emit AddPool(izlude, allocPoint, withUpdate);
    }

    // Update the given pool's KSW allocation point.
    function set(
        address izlude,
        uint64 allocPoint,
        bool withUpdate
    ) external onlyOwner {
        require(izlude != address(0), "invalid izlude");
        PoolInfo storage pool = poolInfo[izlude];
        require(pool.izlude == izlude, "!found");
        if (withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = (totalAllocPoint - pool.allocPoint) + allocPoint;
        pool.allocPoint = allocPoint;
        if (allocPoint > 0) {
            _addTraversal(izlude);
        }
        emit SetPool(izlude, allocPoint, withUpdate);
    }

    /**
     * @dev View function to see pending KSWs on frontend.
     *
     */
    function pendingKSW(address izlude, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[izlude];
        UserInfo storage user = userInfo[izlude][_user];
        uint256 accKSWPerJellopy = pool.accKSWPerJellopy;
        uint256 izludeSupply = IIzludeV2(izlude).totalSupply();
        if (block.timestamp > pool.lastRewardTime && izludeSupply != 0) {
            uint256 time = block.timestamp - pool.lastRewardTime;
            uint256 kswReward = (time * kswPerSecond * pool.allocPoint) / totalAllocPoint;

            uint256 stakingBal = reserve.balances();
            accKSWPerJellopy += (Math.min(kswReward, stakingBal) * 1e12) / izludeSupply;
        }

        uint256 tJellopy = user.jellopy + user.storedJellopy;
        uint256 r = ((tJellopy * accKSWPerJellopy) / 1e12) - user.rewardDebt;
        return r;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        for (uint256 i = 0; i < traversalPools.length; i++) {
            updatePool(traversalPools[i]);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(address izlude) public {
        PoolInfo storage pool = poolInfo[izlude];
        require(pool.izlude == izlude, "!pool");
        if (block.timestamp > pool.lastRewardTime) {
            uint256 izludeSupply = IIzludeV2(izlude).totalSupply();
            if (izludeSupply > 0) {
                uint256 time = block.timestamp - pool.lastRewardTime;
                uint256 kswReward = (time * kswPerSecond * pool.allocPoint) / totalAllocPoint;
                uint256 r = reserve.withdraw(address(this), kswReward);
                pool.accKSWPerJellopy += (r * 1e12) / izludeSupply;
            }
            pool.lastRewardTime = uint64(block.timestamp);
        }
    }

    /**
     * @dev low level deposit 'want' to izlude or staking here
     *
     * 'warning' deposit amount must be guarantee by caller
     */
    function _deposit(
        address _user,
        address izlude,
        IERC20 want,
        uint256 amount
    ) private {
        PoolInfo storage pool = poolInfo[izlude];
        UserInfo storage user = userInfo[izlude][_user];

        updatePool(izlude);
        uint256 tJellopy = user.jellopy + user.storedJellopy;
        if (tJellopy > 0) {
            uint256 pending = ((tJellopy * pool.accKSWPerJellopy) / 1e12) - user.rewardDebt;
            if (pending > 0) {
                IERC20(ksw).transfer(_user, pending);
            }
        }

        // amount must guaranteed by caller
        if (amount > 0) {
            want.safeIncreaseAllowance(izlude, amount);
            uint256 addAmount = IIzludeV2(izlude).deposit(_user, amount);
            tJellopy += addAmount;
            user.jellopy += addAmount;
        }
        user.rewardDebt = (tJellopy * pool.accKSWPerJellopy) / 1e12;
    }

    function harvest(address[] calldata izludes) external nonReentrant {
        for (uint256 i = 0; i < izludes.length; i++) {
            _deposit(msg.sender, izludes[i], IERC20(address(0)), 0);
        }
    }

    function deposit(address izlude, uint256 amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[izlude];
        if (amount > 0) {
            require(_safeERC20TransferIn(pool.want, amount) == amount, "!amount");
        }
        _deposit(msg.sender, izlude, pool.want, amount);
        emit Deposit(msg.sender, izlude, amount);
    }

    function depositFor(
        address user,
        address izlude,
        uint256 amount
    ) external nonReentrant {
        PoolInfo storage pool = poolInfo[izlude];
        if (amount > 0) {
            require(_safeERC20TransferIn(pool.want, amount) == amount, "!amount");
        }
        _deposit(user, izlude, pool.want, amount);
        emit DepositFor(user, izlude, amount);
    }

    function depositToken(
        address izlude,
        IERC20[] calldata tokens,
        uint256[] calldata tokenAmounts,
        uint256 amountOutMin,
        uint256 deadline,
        bytes calldata data
    ) external nonReentrant ensure(deadline) {
        require(tokens.length == tokenAmounts.length, "length mismatch");
        PoolInfo storage pool = poolInfo[izlude];
        IERC20 want = pool.want;

        uint256 beforeBal = want.balanceOf(address(this));
        for (uint256 i = 0; i < tokens.length; i++) {
            require(_safeERC20TransferIn(tokens[i], tokenAmounts[i]) == tokenAmounts[i], "!amount");
            if (tokens[i] != want) {
                tokens[i].safeTransfer(juno, tokenAmounts[i]);
            }
        }
        juno.functionCall(data, "juno: failed");
        uint256 amount = want.balanceOf(address(this)) - beforeBal;
        require(amount >= amountOutMin, "insufficient output amount");

        _deposit(msg.sender, izlude, want, amount);
        emit DepositToken(msg.sender, izlude, tokenAmounts, amount);
    }

    function depositEther(
        address izlude,
        uint256 amountOutMin,
        uint256 deadline,
        bytes calldata data
    ) external payable nonReentrant ensure(deadline) {
        require(msg.value > 0, "!value");
        PoolInfo storage pool = poolInfo[izlude];
        IERC20 want = pool.want;

        uint256 beforeBal = want.balanceOf(address(this));
        {
            WETH.deposit{value: msg.value}();
            WETH.safeTransfer(juno, msg.value);
            juno.functionCall(data, "juno: failed");
        }
        uint256 afterBal = want.balanceOf(address(this));
        uint256 amount = afterBal - beforeBal;
        require(amount >= amountOutMin, "insufficient output amount");

        _deposit(msg.sender, izlude, want, amount);
        emit DepositEther(msg.sender, izlude, msg.value, amount);
    }

    function _withdraw(
        address _user,
        address izlude,
        IERC20 want,
        uint256 jellopyAmount
    ) private returns (uint256 amount) {
        PoolInfo storage pool = poolInfo[izlude];
        UserInfo storage user = userInfo[izlude][_user];
        jellopyAmount = Math.min(user.jellopy, jellopyAmount);

        updatePool(izlude);
        uint256 tJellopy = user.jellopy + user.storedJellopy;
        uint256 pending = ((tJellopy * pool.accKSWPerJellopy) / 1e12) - user.rewardDebt;
        if (pending > 0) {
            IERC20(ksw).transfer(_user, pending);
        }

        tJellopy -= jellopyAmount;
        user.jellopy -= jellopyAmount;
        user.rewardDebt = (tJellopy * pool.accKSWPerJellopy) / 1e12;
        if (jellopyAmount > 0) {
            uint256 wantBefore = want.balanceOf(address(this));
            IIzludeV2(izlude).withdraw(_user, jellopyAmount);
            uint256 wantAfter = want.balanceOf(address(this));
            amount = wantAfter - wantBefore;
        }
    }

    function withdraw(address izlude, uint256 jellopyAmount) external nonReentrant {
        PoolInfo storage pool = poolInfo[izlude];
        uint256 amount = _withdraw(msg.sender, izlude, pool.want, jellopyAmount);
        if (amount > 0) {
            pool.want.safeTransfer(msg.sender, amount);
        }
        emit Withdraw(msg.sender, izlude, jellopyAmount);
    }

    // withdraw from allowed store. send pending reward to owner but transfer want to store and let store handle the rest
    function storeWithdraw(
        address _user,
        address izlude,
        uint256 jellopyAmount
    ) external nonReentrant {
        require(jellopyAmount > 0, "invalid amount");
        PoolInfo storage pool = poolInfo[izlude];
        UserInfo storage user = userInfo[izlude][_user];
        jellopyStorage[_user][izlude][msg.sender] -= jellopyAmount;
        user.storedJellopy -= jellopyAmount;
        user.jellopy += jellopyAmount;

        uint256 amount = _withdraw(_user, izlude, pool.want, jellopyAmount);
        if (amount > 0) {
            pool.want.safeTransfer(msg.sender, amount);
        }
        emit StoreWithdraw(_user, izlude, msg.sender, amount);
    }

    function withdrawToken(
        address izlude,
        IERC20 token,
        uint256 jellopyAmount,
        uint256 amountOutMin,
        uint256 deadline,
        bytes calldata data
    ) external nonReentrant ensure(deadline) {
        PoolInfo storage pool = poolInfo[izlude];
        IERC20 want = pool.want;
        require(token != want, "!want");
        uint256 amount = _withdraw(msg.sender, izlude, want, jellopyAmount);

        uint256 beforeBal = token.balanceOf(address(this));
        {
            want.safeTransfer(juno, amount);
            juno.functionCall(data, "juno: failed");
        }
        uint256 afterBal = token.balanceOf(address(this));
        uint256 amountOut = afterBal - beforeBal;
        require(amountOut >= amountOutMin, "insufficient output amount");

        token.safeTransfer(msg.sender, amountOut);
        emit WithdrawToken(msg.sender, izlude, jellopyAmount, amountOut);
    }

    function withdrawEther(
        address izlude,
        uint256 jellopyAmount,
        uint256 amountOutMin,
        uint256 deadline,
        bytes calldata data
    ) external nonReentrant ensure(deadline) {
        PoolInfo storage pool = poolInfo[izlude];
        uint256 amount = _withdraw(msg.sender, izlude, pool.want, jellopyAmount);

        uint256 beforeBal = WETH.balanceOf(address(this));
        {
            pool.want.safeTransfer(juno, amount);
            juno.functionCall(data, "juno: failed");
        }
        uint256 afterBal = WETH.balanceOf(address(this));
        uint256 amountOut = afterBal - beforeBal;
        require(amountOut >= amountOutMin, "insufficient output amount");

        WETH.withdraw(amountOut);
        payable(msg.sender).sendValue(amountOut);
        emit WithdrawEther(msg.sender, izlude, jellopyAmount, amountOut);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(address izlude) external {
        PoolInfo storage pool = poolInfo[izlude];
        UserInfo storage user = userInfo[izlude][msg.sender];

        uint256 jellopy = user.jellopy;
        user.jellopy = 0;
        user.rewardDebt = (user.storedJellopy * pool.accKSWPerJellopy) / 1e12;
        if (jellopy > 0) {
            IERC20 want = pool.want;
            uint256 wantBefore = want.balanceOf(address(this));
            IIzludeV2(izlude).withdraw(msg.sender, jellopy);
            uint256 wantAfter = want.balanceOf(address(this));
            want.safeTransfer(msg.sender, wantAfter - wantBefore);
        }
        emit EmergencyWithdraw(msg.sender, izlude, jellopy);
    }

    /**
     * @dev Returns the remaining number of jellopy that `store` will be
     * allowed to keep on behalf of `user` through {storeKeepJellopy}. This is
     * zero by default.
     *
     * This value changes when {approveStore} or {storeKeepJellopy} are called.
     */
    function storeAllowance(
        address user,
        address izlude,
        address store
    ) external view returns (uint256) {
        return _storeAllowances[user][izlude][store];
    }

    function _approveStore(
        address user,
        address izlude,
        address store,
        uint256 amount
    ) private {
        require(user != address(0), "approve from the zero address");
        require(izlude != address(0), "approve izlude zero address");
        require(store != address(0), "approve to the zero address");

        _storeAllowances[user][izlude][store] = amount;
        emit StoreApproval(user, izlude, store, amount);
    }

    /**
     * @dev grant store to keep jellopy
     */
    function approveStore(
        address izlude,
        address store,
        uint256 amount
    ) external {
        _approveStore(msg.sender, izlude, store, amount);
    }

    /**
     * @dev Atomically increases the allowance granted to `store` by the caller.
     */
    function increaseStoreAllowance(
        address izlude,
        address store,
        uint256 addedAmount
    ) external {
        _approveStore(msg.sender, izlude, store, _storeAllowances[msg.sender][izlude][store] + addedAmount);
    }

    /**
     * @dev Atomically decreases the allowance granted to `store` by the caller.
     */
    function decreaseStoreAllowance(
        address izlude,
        address store,
        uint256 subtractedAmount
    ) external {
        uint256 currentAllowance = _storeAllowances[msg.sender][izlude][store];
        require(currentAllowance >= subtractedAmount, "decreased allowance below zero");
        unchecked {
            _approveStore(msg.sender, izlude, store, currentAllowance - subtractedAmount);
        }
    }

    /**
     * @dev store pull user jellopy to keep
     */
    function storeKeepJellopy(
        address _user,
        address izlude,
        uint256 amount
    ) external {
        require(amount > 0, "invalid amount");
        UserInfo storage user = userInfo[izlude][_user];
        user.jellopy -= amount;
        user.storedJellopy += amount;
        jellopyStorage[_user][izlude][msg.sender] += amount;

        uint256 currentAllowance = _storeAllowances[_user][izlude][msg.sender];
        require(currentAllowance >= amount, "keep amount exceeds allowance");
        unchecked {
            _approveStore(_user, izlude, msg.sender, currentAllowance - amount);
        }
        emit StoreKeepJellopy(_user, izlude, msg.sender, amount);
    }

    /**
     * @dev store return jellopy to user
     */
    function storeReturnJellopy(
        address _user,
        address izlude,
        uint256 amount
    ) external {
        require(amount > 0, "invalid amount");
        UserInfo storage user = userInfo[izlude][_user];
        jellopyStorage[_user][izlude][msg.sender] -= amount;
        user.storedJellopy -= amount;
        user.jellopy += amount;
        emit StoreReturnJellopy(_user, izlude, msg.sender, amount);
    }

    function setKSWPerSecond(uint256 _kswPerSecond) external onlyOwner {
        massUpdatePools();
        kswPerSecond = _kswPerSecond;
        emit SetKSWPerSecond(_kswPerSecond);
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