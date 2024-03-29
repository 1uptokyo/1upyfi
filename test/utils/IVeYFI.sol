// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IVeYFI {
    struct Point {
        uint128 bias;
        uint128 slope; // - dweight / dt
        uint256 ts;
        uint256 blk; // block
    }

    struct LockedBalance {
        uint256 amount;
        uint256 end;
    }

    struct Kink {
        int128 slope;
        uint256 ts;
    }

    struct Withdrawn {
        uint256 amount;
        uint256 penalty;
    }

    function point_history(address _addr, uint256 _epoch) external view returns (Point memory);

    function locked(address _addr) external view returns (LockedBalance memory);

    function slope_changes(address _addr, uint256 _time) external view returns (int128);

    function slope_changes(address user) external returns (Point memory);

    function get_last_user_point(address user) external returns (Point memory);

    function checkpoint() external;

    function setRewardPool(address rewardPool) external;

    function modify_lock(uint256 amount, uint256 unlockTime, address user) external returns (LockedBalance memory);

    function withdraw() external returns (Withdrawn memory);

    function find_epoch_by_timestamp(address user, uint256 ts) external view returns (uint256);

    function balanceOf(address user, uint256 ts) external view returns (uint256);

    function getPriorVotes(address user, uint256 height) external view returns (uint256);

    function totalSupply(uint256 ts) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function totalSupplyAt(uint256 height) external view returns (uint256);

    function decimals() external view returns (uint256);
}
