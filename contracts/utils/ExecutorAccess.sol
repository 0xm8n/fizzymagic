// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract HydraAccess is AccessControl {
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    modifier onlyHydra() {
        if (!hasRole(EXECUTOR_ROLE, _msgSender())) {
            revert(string(abi.encodePacked("AccessControl: caller is not the hydra")));
        }
        _;
    }
}
