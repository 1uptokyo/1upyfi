// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console2 as console} from "forge-std/console2.sol";
import {IVestingEscrow} from "../../utils/IVestingEscrow.sol";

contract VestingEscrowHandler is CommonBase, StdCheats, StdUtils {
    IVestingEscrow private vestingEscrow;

    uint256 public vestedAmount;

    constructor(IVestingEscrow _vestingEscrow, uint256 _vestedAmount) {
        vestingEscrow = _vestingEscrow;
        vestedAmount = _vestedAmount;
    }

    function unclaimed() external view returns (uint256) {
        return vestingEscrow.unclaimed();
    }

    function total_claimed() external view returns (uint256) {
        return vestingEscrow.total_claimed();
    }

    function locked() external view returns (uint256) {
        return vestingEscrow.locked();
    }

    function sum_unclaimed_claimed_locked() external view returns (uint256) {
        return vestingEscrow.unclaimed() + vestingEscrow.total_claimed() + vestingEscrow.locked();
    }

    function claim() external returns (uint256) {
        hoax(vestingEscrow.recipient());
        return vestingEscrow.claim();
    }

    function claim(address _sender) external returns (uint256) {
        if (vestingEscrow.open_claim()) {
            hoax(_sender);
            return vestingEscrow.claim(vestingEscrow.recipient());
        } else {
            hoax(vestingEscrow.recipient());
            return vestingEscrow.claim();
        }
    }
}
