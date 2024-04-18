// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console2 as console} from "forge-std/console2.sol";
import {BaseTest} from "../utils/Base.t.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IVeYFI} from "../utils/IVeYFI.sol";
import {IProxy} from "../utils/IProxy.sol";
import {IStakingRewards} from "../utils/IStakingRewards.sol";
import {ILiquidLocker} from "../utils/ILiquidLocker.sol";
import {IMockToken} from "../mocks/IMockToken.sol";
import {LiquidLockerHandler} from "./handlers/LiquidLockerHandler.sol";
import {LiquidLockerActorManager} from "./managers/LiquidLockerActorManager.sol";

contract ActorLiquidLockerTest is BaseTest {
    uint256 private constant TOTAL_HANDLERS = 10;
    uint256 private constant MAX_SKIP_SECONDS = 10 * 86400;
    uint256 private constant SCALE = 69_420;

    address private _owner;
    address private _sender;
    IMockToken internal _token;
    IVeYFI internal _veYfi;
    IProxy internal _proxy;
    ILiquidLocker internal _liquidLocker;
    IERC4626 internal _staking;
    IStakingRewards internal _stakingRewards;
    LiquidLockerActorManager public manager;
    LiquidLockerHandler[] public handlers;

    function setUp() external {
        _owner = address(0x99999999);
        _sender = address(0x1);

        (_liquidLocker, _token, _veYfi, _proxy, _staking, _stakingRewards) = _deployLiquidLocker(_owner);
        _token = IMockToken(_liquidLocker.token());

        vm.label(_owner, "owner");
        vm.label(_sender, "sender");
        vm.label(address(_liquidLocker), "liquidLocker");
        vm.label(address(_veYfi), "veYfi");
        vm.label(address(_proxy), "proxy");
        vm.label(address(_token), "token");

        for (uint256 i = 0; i < TOTAL_HANDLERS; ++i) {
            LiquidLockerHandler handler = new LiquidLockerHandler(
                _liquidLocker
            );
            vm.label(
                address(handler),
                string.concat("handler_", vm.toString(i))
            );
            handlers.push(handler);
        }
        manager = new LiquidLockerActorManager(handlers, MAX_SKIP_SECONDS);
        targetContract(address(manager));
    }

    function invariant_veyfi_balance_of_yfi_eq_total_deposited_amount()
        external
    {
        uint256 totalDepositedAmount = manager.totalDepositedAmount();
        uint256 veYFIBalanceOfYFI = _token.balanceOf(address(_veYfi));
        assertEq(
            veYFIBalanceOfYFI,
            totalDepositedAmount,
            "Invalid veYFI balance of YFI eq total deposited amount"
        );
    }

    function invariant_total_supply_eq_total_deposited_amount()
        external
    {
        uint256 totalDepositedAmount = manager.totalDepositedAmount();
        
        assertEq(
            _liquidLocker.totalSupply(),
            totalDepositedAmount * SCALE,
            "Invalid total supply eq total deposited amount"
        );
    }
}
