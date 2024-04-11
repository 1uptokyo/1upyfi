// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IVestingEscrowDepositor {

    function deposit(uint256 _amount) external returns (uint256);

    function rescue(address _token, uint256 _amount) external;

    function staking() external view returns (IERC4626);
}
