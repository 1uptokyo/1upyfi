// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IVestingEscrowFactory {
    function TARGET() external view returns (address);

    function deploy_vesting_contract(
        address _token,
        address _recipient,
        uint256 _amount,
        uint256 _vestingDuration,
        uint256 _vestingStart,
        uint256 _cliffLength,
        bool _openClaim,
        address _owner
    ) external returns (address);

    function deploy_vesting_contract(
        address _token,
        address _recipient,
        uint256 _amount,
        uint256 _vestingDuration,
        uint256 _vestingStart,
        uint256 _cliffLength,
        bool _openClaim
    ) external returns (address);

    function deploy_vesting_contract(
        address _token,
        address _recipient,
        uint256 _amount,
        uint256 _vestingDuration,
        uint256 _vestingStart,
        uint256 _cliffLength
    ) external returns (address);

    function deploy_vesting_contract(
        address _token,
        address _recipient,
        uint256 _amount,
        uint256 _vestingDuration,
        uint256 _vestingStart
    ) external returns (address);

    function deploy_vesting_contract(
        address _token,
        address _recipient,
        uint256 _amount,
        uint256 _vestingDuration
    ) external returns (address);
}
