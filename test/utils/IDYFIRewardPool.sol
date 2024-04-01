// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IDYFIRewardPool {
    function WEEK() external view returns (uint256);

    function TOKEN_CHECKPOINT_DEADLINE() external view returns (uint256);

    function DYFI() external view returns (address);

    function VEYFI() external view returns (address);

    function start_time() external view returns (uint256);

    function time_cursor() external view returns (uint256);

    function time_cursor_of(address) external view returns (uint256);

    function last_token_time() external view returns (uint256);

    function tokens_per_week(uint256) external view returns (uint256);

    function token_last_balance() external view returns (uint256);

    function ve_supply(uint256) external view returns (uint256);

    function checkpoint_token() external;

    function checkpoint_total_supply() external;

    function claim(address _user) external returns (uint256);

    function burn(uint256 _amount) external returns (bool);

    function token() external view returns (address);

    function veyfi() external view returns (address);
}
