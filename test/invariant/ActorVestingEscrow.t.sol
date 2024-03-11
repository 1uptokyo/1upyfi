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
import {IVestingEscrowFactory} from "../utils/IVestingEscrowFactory.sol";
import {VestingEscrowHandler} from "./handlers/VestingEscrowHandler.sol";
import {VestingEscrowActorManager} from "./managers/VestingEscrowActorManager.sol";

contract ActorVestingEscrowTest is BaseTest, FoundryRandom {
    uint256 private constant TOTAL_HANDLERS = 10;
    uint256 private constant MAX_SKIP_SECONDS = 10 * 86400;

    address private owner;
    address private sender;
    IMockToken internal _token;
    IVestingEscrowFactory internal _factory;
    VestingEscrowActorManager public manager;
    VestingEscrowHandler[] public handlers;

    function setUp() external {
        owner = address(0x99999999);
        sender = address(0x1);

        _token = _deployToken(owner);
        _factory = _deployVestingEscrowFactory(owner);

        vm.label(owner, "owner");
        vm.label(sender, "sender");
        vm.label(address(_factory), "escrowFactory");
        vm.label(address(_token), "token");

        for (uint256 i = 0; i < TOTAL_HANDLERS; ++i) {
            uint256 _amount = randomNumber(1, type(uint64).max / TOTAL_HANDLERS);
            uint256 _vestingDuration = randomNumber(1, type(uint32).max);
            address _recipient = address(uint160(randomNumber(1, type(uint160).max)));
            uint256 _cliffLength = randomNumber(1, _vestingDuration - 1);// TODO 0
            uint256 _vestingStart = randomNumber(block.timestamp, block.timestamp + 2 + type(uint32).max - _vestingDuration);// TODO block.timestamp +1;
            bool _openClaim = randomNumber(0, 100) < 50; // TODO CHECK VALUES!!!!

            _token.mint(sender, _amount);
            vm.startPrank(sender);
            _token.approve(address(_factory), _amount);
            address vestingEscrow = _factory.deploy_vesting_contract(
                address(_token),
                _recipient,
                _amount,
                _vestingDuration,
                _vestingStart,
                _cliffLength,
                _openClaim,
                owner
            );
            vm.stopPrank();
            vm.label(vestingEscrow, "vestingEscrow");
            VestingEscrowHandler handler = new VestingEscrowHandler(IVestingEscrow(vestingEscrow), _amount);
            handlers.push(handler);
        }
        manager = new VestingEscrowActorManager(handlers, MAX_SKIP_SECONDS);
        targetContract(address(manager));
    }

    function invariant_vested_eq_sum_unclaimed_claimed_locked() external {
        for (uint256 i = 0; i < TOTAL_HANDLERS; ++i) {
            assertEq(
                handlers[i].sum_unclaimed_claimed_locked(),
                handlers[i].vestedAmount(),
                "Vested amount not eq sum of unclaimed, claimed and locked"
            );
        }
    }
}
