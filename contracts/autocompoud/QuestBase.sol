// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./PerfCollector.sol";
import "./interfaces/IGasPrice.sol";
import "./interfaces/IQuest.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Router02.sol";

abstract contract QuestBase is Ownable, Pausable, PerfCollector, IQuest {
    
    using SafeERC20 for IERC20;
    using Address for address payable;

    address public router;
    address public guild;
    address public guildReserve;
    address public executor;
    
    uint256 public immutable pid;
    address public immutable override questLp;
    address public immutable lpToken0;
    address public immutable lpToken1;

    // Tokens used
    address public gasPrice = 0xc558252b50920a21f4AE3225E1Ed7D250E5D5593;
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant FZM = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    // Routes
    address[] public rwTokenToWbnbRoute;
    address[] public rwTokenToLp0Route;
    address[] public rwTokenToLp1Route;
    address[] public fzmToLp0Route;
    address[] public fzmToLp1Route;

    event SetRouter(address router);
    event SetGuildReserve(address guildReserve);
    event SetExecutor(address executor);
    event SetGasPrice(address gasPrice);
    event Compound(address indexed compound);

    constructor(
        address _router,
        address _guild,
        address _guildReserve,
        address _executor,
        address _masterchef,
        uint256 _pid,
        address _rwToken,
        address[] _rwTokenToLp0Route,
        address[] _rwTokenToLp1Route
    ) {
        router = _router;
        guild = _guild;
        guildReserve = _guildReserve;
        executor = _executor;
        pid = _pid;
        questLp = IPcsMasterChef(_masterchef).poolInfo(_pid).lpToken;
        lpToken0 = IUniswapV2Pair(questLp).token0();
        lpToken1 = IUniswapV2Pair(questLp).token1();

        rwTokenToWbnbRoute = [_rwToken, Wbnb];
        if (lpToken0 != _rwToken) {
            require(_rwTokenToLp0Route[0] == _rwToken, "invalid lp 0 route");
            require(_rwTokenToLp0Route[_rwTokenToLp0Route.length - 1] == lpToken0, "invalid lp 0 route");
            require(
                IUniswapV2Router02(router).getAmountsOut(1 ether, _rwTokenToLp0Route)[_rwTokenToLp0Route.length - 1] > 0,
                "invalid lp 0 route"
            );
            rwTokenToLp0Route = _rwTokenToLp0Route;
        }

        if (lpToken1 != _rwToken) {
            require(_rwTokenToLp1Route[0] == _rwToken, "invalid lp 1 route");
            require(_rwTokenToLp1Route[_rwTokenToLp1Route.length - 1] == lpToken1, "invalid lp 1 route");
            require(
                IUniswapV2Router02(router).getAmountsOut(1 ether, _rwTokenToLp1Route)[_rwTokenToLp1Route.length - 1] > 0,
                "invalid lp 1 route"
            );
            rwTokenToLp1Route = _rwTokenToLp1Route;
        }

        _giveAllowances();
    }

    // verifies that the caller is not a contract.
    modifier onlyEOA() {
        require(msg.sender == tx.origin, "!EOA");
        _;
    }

    modifier onlyGuild() {
        require(msg.sender == guild, "!guild");
        _;
    }

    modifier onlyEOAandGuild() {
        require(tx.origin == msg.sender || msg.sender == guild, "!contract");
        _;
    }

    modifier onlyExecutor() {
        require(executor == address(0) || msg.sender == executor, "!executor");
        _;
    }

    modifier gasThrottle() {
        require(tx.gasprice <= IGasPrice(gasPrice).maxGasPrice(), "gas is too high!");
        _;
    }

    function setRouter(address _router) external onlyOwner {
        router = _router;
        emit SetRouter(_router);
    }

    function setGuild(address _guild) external onlyOwner {
        require(guild == address(0), "already set");
        guild = _guild;
    }

    function setGuildReserve(address _guildReserve) external onlyOwner {
        guildReserve = _guildReserve;
        emit SetGuildReserve(_guildReserve);
    }

    function setExecutor(address _executor) external onlyOwner {
        executor = _executor;
        emit SetExecutor(_executor);
    }

    function setGasPrice(address _gasPrice) external onlyOwner {
        gasPrice = _gasPrice;
        emit SetGasPrice(_gasPrice);
    }

    // performance fees
    function chargeFees() internal {
        uint256 toBnb = (IERC20(CAKE).balanceOf(address(this)) * perfFee) / maxPerfFee;
        IUniswapV2Router02(router).swapExactTokensForETH(toBnb, 0, cakeToWbnbRoute, address(this), block.timestamp);

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
            IUniswapV2Router02(router).swapExactTokensForTokens(cakeHalf, 0, cakeToLp0Route, address(this), block.timestamp);
        }

        if (lpToken1 != CAKE) {
            IUniswapV2Router02(router).swapExactTokensForTokens(cakeHalf, 0, cakeToLp1Route, address(this), block.timestamp);
        }

        IUniswapV2Router02(router).addLiquidity(
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

    // calculate the total underlaying 'questLp' held by the strat.
    function balanceOf() external view override returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'questLp' this contract holds.
    function balanceOfWant() public view override returns (uint256) {
        return IERC20(questLp).balanceOf(address(this));
    }

    function balanceOfMasterChef() external view override returns (uint256) {
        return IERC20(questLp).balanceOf(MASTERCHEF);
    }

    function pause() public override onlyOperator {
        _pause();

        _removeAllowances();
    }

    function unpause() external override onlyOperator {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function paused() public view override(IQuest, Pausable) returns (bool) {
        return super.paused();
    }

    function _giveAllowances() internal {
        IERC20(questLp).safeApprove(MASTERCHEF, type(uint256).max);
        IERC20(CAKE).safeApprove(router, type(uint256).max);

        // lp token 0 and 1 maybe cake so approve 0 is needed here
        IERC20(lpToken0).safeApprove(router, 0);
        IERC20(lpToken0).safeApprove(router, type(uint256).max);

        IERC20(lpToken1).safeApprove(router, 0);
        IERC20(lpToken1).safeApprove(router, type(uint256).max);
    }

    function _removeAllowances() internal {
        IERC20(questLp).safeApprove(MASTERCHEF, 0);
        IERC20(CAKE).safeApprove(router, 0);
        IERC20(lpToken0).safeApprove(router, 0);
        IERC20(lpToken1).safeApprove(router, 0);
    }

    receive() external payable {
        require(msg.sender == router, "reject");
    }
}
