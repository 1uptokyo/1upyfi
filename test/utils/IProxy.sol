// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IProxy {
    function voting_escrow() external view returns (address);

    function management() external view returns (address);

    function pending_management() external view returns (address);

    function operators(address _operator) external view returns (bool);

    function messages(bytes32 _message) external view returns (bool);

    function MAX_SIZE() external view returns (uint256);

    function EIP1271_MAGIC_VALUE() external view returns (bytes4);

    function isValidSignature(
        bytes32 _hash,
        bytes memory _signature
    ) external view returns (bytes4);

    function call(address _target, bytes calldata _data) external payable;

    function modify_lock(uint256 _amount, uint256 _unlock_time) external;

    function set_signed_message(bytes32 _hash, bool _signed) external;

    function set_operator(address _operator, bool _flag) external;

    function set_management(address _management) external;

    function accept_management() external;
}
