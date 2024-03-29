// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface ILiquidLocker {
    function deposit(uint256 _amount) external;

    function deposit(uint256 _amount, address _receiver) external;

    function mint() external returns (uint256);

    function mint(address _receiver) external returns (uint256);

    function extend_lock() external;

    function transfer(address _to, uint256 _value) external returns (bool);

    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) external returns (bool);

    function approve(address _spender, uint256 _value) external returns (bool);

    function token() external view returns (address);

    function voting_escrow() external view returns (address);

    function proxy() external view returns (address);

    function totalSupply() external view returns (uint256);

    function balanceOf(address _account) external view returns (uint256);

    function allowance(
        address _owner,
        address _spender
    ) external view returns (uint256);

    function decimals() external view returns (uint8);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);
}
