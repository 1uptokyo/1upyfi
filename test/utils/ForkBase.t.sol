// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";

abstract contract ForkBaseTest is Test {

    string constant ETH_MAINNET = "eth_mainnet";
    string constant BSC_MAINNET = "bsc_mainnet";
    string constant MATIC_MAINNET = "matic_mainnet";
    string constant ARB_MAINNET = "arb_mainnet";
    string constant OP_MAINNET = "op_mainnet";
    string constant AVAX_MAINNET = "avax_mainnet";
    string constant FTM_MAINNET = "ftm_mainnet";
    string constant BASE_MAINNET = "base_mainnet";
    string constant ZKSYNC_MAINNET = "zksync_mainnet";

    mapping(string => uint256) internal _forkIds;

    function _createSelectFork(string memory name) internal returns (uint256) {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl(name));
        _forkIds[name] = forkId;
        _assertForkIsActive(forkId);
        return forkId;
    }

    function _selectFork(string memory name) internal {
        uint256 forkId = _forkIds[name];
        require(forkId != 0, "!forkId");
        vm.selectFork(forkId);
        _assertForkIsActive(forkId);
    }

    function _assertForkIsActive(uint256 forkId) internal {
        assertEq(vm.activeFork(), forkId, "!forkId");
    }
}
