// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IProxy} from "../utils/IProxy.sol";

contract MockProxy is IProxy {
    function voting_escrow() external view override returns (address) {}

    function management() external view override returns (address) {}

    function pending_management() external view override returns (address) {}

    function operators(
        address _operator
    ) external view override returns (bool) {}

    function messages(bytes32 _message) external view override returns (bool) {}

    function MAX_SIZE() external view override returns (uint256) {}

    function EIP1271_MAGIC_VALUE() external view override returns (bytes4) {}

    function isValidSignature(
        bytes32 _hash,
        bytes memory _signature
    ) external view override returns (bytes4) {}

    function call(
        address _target,
        bytes calldata _data
    ) external payable override {}

    function modify_lock(
        uint256 _amount,
        uint256 _unlock_time
    ) external override {}

    function set_signed_message(
        bytes32 _hash,
        bool _signed
    ) external override {}

    function set_operator(address _operator, bool _flag) external override {}

    function set_management(address _management) external override {}

    function accept_management() external override {}
}
