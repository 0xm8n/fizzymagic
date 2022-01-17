// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import './IERC20.sol';

interface IFizzyERC20 is IERC20 {

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}
