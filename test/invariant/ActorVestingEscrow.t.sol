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
import {IVestingEscrowDepositor} from "../utils/IVestingEscrowDepositor.sol";
import {IVestingEscrowFactory} from "../utils/IVestingEscrowFactory.sol";
import {VestingEscrowHandler} from "./handlers/VestingEscrowHandler.sol";
import {VestingEscrowActorManager} from "./managers/VestingEscrowActorManager.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract ActorVestingEscrowTest is BaseTest, FoundryRandom {
    uint256 private constant TOTAL_HANDLERS = 10;
    uint256 private constant MAX_SKIP_SECONDS = 10 * 86400;

    address private owner;
    address private sender;
    IMockToken internal _token;
    IMockToken internal _llToken;
    IERC4626 public staking;
    IVestingEscrowFactory internal _factory;
    VestingEscrowActorManager public manager;
    VestingEscrowHandler[] public handlers;

    function setUp() external {
        owner = address(0x99999999);
        sender = address(0x1);

        _token = _deployToken(owner);
        _llToken = _deployToken(owner);
        _factory = _deployVestingEscrowFactory(owner, address(_token), owner);

        vm.label(owner, "owner");
        vm.label(sender, "sender");
        vm.label(address(_factory), "escrowFactory");
        vm.label(address(_token), "token");
        
        staking = _deployStakingMock(owner);
        IVestingEscrowDepositor _depositor = _deployVestingEscrowDepositor(
            owner,
            address(_token),
            address(_llToken),
            address(staking),
            owner
        );
        vm.startPrank(owner);
        _factory.set_liquid_locker(address(_llToken), address(_depositor));
        vm.stopPrank();

        for (uint256 i = 0; i < TOTAL_HANDLERS; ++i) {
            uint256 _amount = randomNumber(1, type(uint64).max / TOTAL_HANDLERS);
            uint256 _vestingDuration = randomNumber(1, type(uint32).max);
            address _recipient = address(uint160(randomNumber(1, type(uint160).max)));
            uint256 _cliffLength = randomNumber(1, _vestingDuration - 1);
            uint256 _vestingStart = randomNumber(block.timestamp, block.timestamp + 2 + type(uint32).max - _vestingDuration);
            bool _openClaim = randomNumber(0, 100) < 50;

            _token.mint(sender, _amount);
            vm.startPrank(sender);
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
                address(_llToken),
                _amount,
                _openClaim
            );
            vm.stopPrank();
            vm.label(_vestingEscrow, "vestingEscrow");
            VestingEscrowHandler handler = new VestingEscrowHandler(IVestingEscrow(_vestingEscrow), llTokens);
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
