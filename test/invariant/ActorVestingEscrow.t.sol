// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { FoundryRandom } from "foundry-random/FoundryRandom.sol";
import {Test} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console2 as console} from "forge-std/console2.sol";
import {BaseTest} from "../utils/Base.t.sol";

import {IMockToken} from "../mocks/IMockToken.sol";
import {IVestingEscrow} from "../utils/IVestingEscrow.sol";
import {ILiquidLocker} from "../utils/ILiquidLocker.sol";
import {IProxy} from "../utils/IProxy.sol";
import {IVeYFI} from "../utils/IVeYFI.sol";
import {IVestingEscrowDepositor} from "../utils/IVestingEscrowDepositor.sol";
import {IVestingEscrowFactory} from "../utils/IVestingEscrowFactory.sol";
import {VestingEscrowHandler} from "./handlers/VestingEscrowHandler.sol";
import {VestingEscrowActorManager} from "./managers/VestingEscrowActorManager.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract ActorVestingEscrowTest is BaseTest, FoundryRandom {
    uint256 private constant TOTAL_HANDLERS = 10;
    uint256 private constant MAX_SKIP_SECONDS = 10 * 86400;

    address internal _owner;
    address internal _sender;
    IMockToken internal _token;
    ILiquidLocker internal _liquidLocker;
    IVeYFI internal _veYFI;
    IProxy internal _proxy;
    IERC4626 internal _staking;
    IVestingEscrowFactory internal _factory;
    VestingEscrowActorManager public manager;
    VestingEscrowHandler[] internal _handlers;

    function setUp() external {
        _owner = address(0x99999999);
        _sender = address(0x1);
        _token = _deployToken(_owner);

        IVestingEscrow _target = _deployVestingEscrowTarget(_owner);

        (
            _liquidLocker,
            _token, /* yfi */
            _veYFI,
            _proxy,
            _staking,
        ) = _deployLiquidLocker(
            _owner
        );

        _factory = _deployVestingEscrowFactory(_owner, address(_target), address(_token), _owner);

        IVestingEscrowDepositor _depositor = _deployVestingEscrowDepositor(
            _owner,
            address(_token),
            address(_liquidLocker),
            address(_staking),
            _owner
        );
        vm.startPrank(_owner);
        _factory.set_liquid_locker(address(_staking), address(_depositor));
        vm.stopPrank();

        vm.startPrank(address(_liquidLocker));
        _proxy.call(address(_token), abi.encodeWithSelector(_token.approve.selector, address(_veYFI), type(uint256).max));
        vm.stopPrank();

        vm.label(_owner, "owner");
        vm.label(_sender, "sender");
        vm.label(address(_factory), "escrowFactory");
        vm.label(address(_token), "token");
        vm.label(address(_target), "target");
        vm.label(address(_liquidLocker), "liquidLocker");
        vm.label(address(_staking), "staking");
        vm.label(address(_proxy), "proxy");
        vm.label(address(_veYFI), "veYFI");
        vm.label(address(_depositor), "escrowDepositor");

        for (uint256 i = 0; i < TOTAL_HANDLERS; ++i) {
            uint256 _amount = randomNumber(1e18, type(uint64).max / TOTAL_HANDLERS);
            uint256 _vestingDuration = randomNumber(1, type(uint32).max);
            address _recipient = address(uint160(randomNumber(1, type(uint160).max)));
            uint256 _cliffLength = randomNumber(1, _vestingDuration - 1);
            uint256 _vestingStart = randomNumber(block.timestamp, block.timestamp + 2 + type(uint32).max - _vestingDuration);
            bool _openClaim = randomNumber(0, 100) < 50;

            _token.mint(_sender, _amount);
            vm.startPrank(_sender);
            _token.approve(address(_factory), _amount);
            uint256 vestIdx = _factory.create_vest(
                _recipient,
                _amount,
                _vestingDuration,
                _vestingStart,
                _cliffLength
            );
            vm.stopPrank();
            vm.startPrank(_recipient);
            (address _vestingEscrow, uint256 llTokens) = _factory.deploy_vesting_contract(
                vestIdx,
                address(_staking),
                _amount,
                _openClaim
            );
            vm.stopPrank();
            vm.label(_vestingEscrow, string.concat("vestingEscrow_", vm.toString(vestIdx)));
            VestingEscrowHandler handler = new VestingEscrowHandler(IVestingEscrow(_vestingEscrow), llTokens);
            vm.label(address(handler), string.concat("handler_", vm.toString(vestIdx)));
            _handlers.push(handler);
        }
        manager = new VestingEscrowActorManager(_handlers, MAX_SKIP_SECONDS);
        vm.label(address(manager), "actorManager");
        targetContract(address(manager));
    }

    function invariant_vested_eq_sum_unclaimed_claimed_locked() external {
        for (uint256 i = 0; i < TOTAL_HANDLERS; ++i) {
            assertEq(
                _handlers[i].sum_unclaimed_claimed_locked(),
                _handlers[i].vestedAmount(),
                "Vested amount not eq sum of unclaimed, claimed and locked"
            );
        }
    }
}
