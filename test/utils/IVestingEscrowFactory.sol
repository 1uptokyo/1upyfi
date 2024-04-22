// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IVestingEscrowFactory {
    function TARGET() external view returns (address);


    function create_vest(
        address _recipient,
        uint256 _amount,
        uint256 _vestingDuration,
        uint256 _vestingStart,
        uint256 _cliffLength
    ) external returns (uint256);

    function create_vest(
        address _recipient,
        uint256 _amount,
        uint256 _vestingDuration,
        uint256 _vestingStart
    ) external returns (uint256);

    function create_vest(
        address _recipient,
        uint256 _amount,
        uint256 _vestingDuration
    ) external returns (uint256);

    function deploy_vesting_contract(
        uint256 _idx,
        address _token,
        uint256 _amount,
        bool _openClaim
    ) external returns (address, uint256);

    function deploy_vesting_contract(
        uint256 _idx,
        address _token,
        uint256 _amount
    ) external returns (address);

    function set_liquid_locker(address liquid_locker, address depositor) external;
}
