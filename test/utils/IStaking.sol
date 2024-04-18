// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IStaking is IERC4626 {
    function set_rewards(address _rewards) external;

    function asset() external view returns (address);
    function management() external view returns (address);
    function pending_management() external view returns (address);
    function rewards() external view returns (address);
}
