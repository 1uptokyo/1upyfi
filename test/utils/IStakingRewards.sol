// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStakingRewards {
    function deposit(uint256 _amount) external;

    function proxy() external view returns (address);

    function staking() external view returns (IERC20);

    function locking_token() external view returns (IERC20);

    function discount_token() external view returns (IERC20);

    function management() external returns (address);

    function pending_management() external returns (address);

    function treasury() external returns (address);

    function pending(address _account) external view returns (uint256, uint256);

    function claimable(
        address _account
    ) external view returns (uint256, uint256);

    function claim() external payable returns (uint256, uint256);

    function claim(
        address _receiver
    ) external payable returns (uint256, uint256);

    function claim(
        address _receiver,
        bytes calldata _redeem_data
    ) external payable returns (uint256, uint256);

    function harvest(
        uint256 _lt_amount,
        uint256 _dt_amount,
        address _receiver
    ) external;

    function report(
        address _account,
        uint256 _balance,
        uint256 _supply
    ) external;

    function pending_fees() external view returns (uint256, uint256);

    function claim_fees() external;

    function set_redeemer(address _redeemer) external;

    function set_treasury(address _treasury) external;

    function set_fee_rate(uint256 _idx, uint256 _fee_rate) external;
}
