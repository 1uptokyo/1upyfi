// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {StdUtils} from "forge-std/StdUtils.sol";

abstract contract UintUtils is StdUtils {
    function _uint256ToAddress(uint256 seed) internal pure returns (address) {
        return address(uint160(bound(seed, 1, type(uint160).max)));
    }
}
