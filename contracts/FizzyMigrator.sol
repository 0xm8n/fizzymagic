// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import './utils/TransferHelper.sol';

import './interfaces/IFizzyMigrator.sol';
import './interfaces/Old/IOldFizzyFactory.sol';
import './interfaces/Old/IOldFizzyExchange.sol';
import './interfaces/IFizzyRouter01.sol';
import './standards/IERC20.sol';

contract FizzyMigrator is IFizzyMigrator {
    uint256 private constant MAX_UINT256 = (2**256) - 1;
    IOldFizzyFactory immutable factoryV1;
    IFizzyRouter01 immutable router;

    constructor(address _factoryV1, address _router) {
        factoryV1 = IOldFizzyFactory(_factoryV1);
        router = IFizzyRouter01(_router);
    }

    // needs to accept ETH from any v1 exchange and the router. ideally this could be enforced, as in the router,
    // but it's not possible because it requires a call to the v1 factory, which takes too much gas
    receive() external payable {}

    function migrate(address token, uint amountTokenMin, uint amountETHMin, address to, uint deadline)
        external
        override
    {
        IOldFizzyExchange exchangeV1 = IOldFizzyExchange(factoryV1.getExchange(token));
        uint liquidityV1 = exchangeV1.balanceOf(msg.sender);
        require(exchangeV1.transferFrom(msg.sender, address(this), liquidityV1), 'TRANSFER_FROM_FAILED');
        (uint amountETHV1, uint amountTokenV1) = exchangeV1.removeLiquidity(liquidityV1, 1, 1, MAX_UINT256);
        TransferHelper.safeApprove(token, address(router), amountTokenV1);
        (uint amountTokenV2, uint amountETHV2,) = router.addLiquidityETH{value: amountETHV1}(
            token,
            amountTokenV1,
            amountTokenMin,
            amountETHMin,
            to,
            deadline
        );
        if (amountTokenV1 > amountTokenV2) {
            TransferHelper.safeApprove(token, address(router), 0); // be a good blockchain citizen, reset allowance to 0
            TransferHelper.safeTransfer(token, msg.sender, amountTokenV1 - amountTokenV2);
        } else if (amountETHV1 > amountETHV2) {
            // addLiquidityETH guarantees that all of amountETHV1 or amountTokenV1 will be used, hence this else is safe
            TransferHelper.safeTransferETH(msg.sender, amountETHV1 - amountETHV2);
        }
    }
}
