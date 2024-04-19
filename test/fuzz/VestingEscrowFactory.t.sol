// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {console2} from "forge-std/Test.sol";
import {IVestingEscrow} from "../utils/IVestingEscrow.sol";
import {IVestingEscrowFactory} from "../utils/IVestingEscrowFactory.sol";
import {IVestingEscrowDepositor} from "../utils/IVestingEscrowDepositor.sol";
import {FoundryRandom} from "foundry-random/FoundryRandom.sol";
import {ILiquidLocker} from "../utils/ILiquidLocker.sol";
import {IStakingRewards} from "../utils/IStakingRewards.sol";
import {IVeYFI} from "../utils/IVeYFI.sol";
import {IProxy} from "../utils/IProxy.sol";
import {IMockToken} from "../mocks/IMockToken.sol";
import {BaseTest} from "../utils/Base.t.sol";
import {UintUtils} from "../utils/UintUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract VestingEscrowFactoryTest is BaseTest, UintUtils, FoundryRandom {
    IVestingEscrowFactory public escrowFactory;
    IVeYFI public veYFI;
    IMockToken public token;
    ILiquidLocker public liquidLocker;
    IERC4626 public staking;
    address public owner;
    IProxy public proxy;
    IStakingRewards public stakingRewards;

    function setUp() public {
        owner = address(0x3);
        IVestingEscrow _target = _deployVestingEscrowTarget(owner);

        (
            liquidLocker,
            token /* yfi */,
            veYFI,
            proxy,
            staking,
            stakingRewards
        ) = _deployLiquidLocker(owner);

        escrowFactory = _deployVestingEscrowFactory(
            owner,
            address(_target),
            address(token),
            owner
        );

        vm.label(owner, "owner");
        vm.label(address(escrowFactory), "escrowFactory");
        vm.label(address(token), "token");
        vm.label(address(_target), "target");
        vm.label(address(liquidLocker), "liquidLocker");
        vm.label(address(staking), "staking");
        vm.label(address(proxy), "proxy");
    }

    function _randomAddress(uint256 _id) internal returns (address) {
        address _address = _uint256ToAddress(_id);
        bool isAddressOk = _address != address(0x0) &&
            _address != address(this) &&
            _address != address(owner);
        return
            isAddressOk
                ? _address
                : _uint256ToAddress(
                    randomNumber(type(uint16).max, type(uint160).max)
                );
    }

    function test_deploy_vesting_contract_valid(
        uint128 _vestingDuration,
        bool _openClaim,
        address _owner
    ) public {
        vm.assume(_vestingDuration > 0);

        address _recipient = _uint256ToAddress(
            randomNumber(type(uint16).max, type(uint128).max)
        );
        address _vestCreator = _uint256ToAddress(
            randomNumber(type(uint128).max, type(uint256).max)
        );
        vm.assume(_recipient != _vestCreator);
        uint256 _amount = randomNumber(1e18, type(uint64).max);

        uint256 _cliffLength = randomNumber(0, _vestingDuration);

        uint256 _vestingStart = block.timestamp +
            randomNumber(0, _vestingDuration);
        vm.assume(_owner != address(0x0));

        token.mint(_owner, _amount);
        vm.startPrank(_owner);
        token.approve(address(escrowFactory), _amount);
        vm.stopPrank();

        IVestingEscrowDepositor _depositor = _deployVestingEscrowDepositor(
            _owner,
            address(token),
            address(liquidLocker),
            address(staking),
            _owner
        );
        vm.startPrank(owner);
        escrowFactory.set_liquid_locker(address(staking), address(_depositor));
        vm.stopPrank();

        vm.startPrank(address(liquidLocker));
        proxy.call(
            address(token),
            abi.encodeWithSelector(
                token.approve.selector,
                address(veYFI),
                type(uint256).max
            )
        );
        vm.stopPrank();

        vm.startPrank(_vestCreator);
        token.mint(_vestCreator, _amount);
        token.approve(address(escrowFactory), _amount);
        uint256 vestIdx = escrowFactory.create_vest(
            _recipient,
            _amount,
            _vestingDuration,
            _vestingStart,
            _cliffLength
        );
        vm.stopPrank();
        vm.startPrank(_recipient);
        (address _vestingEscrow, uint256 llTokens) = escrowFactory
            .deploy_vesting_contract(
                vestIdx,
                address(staking),
                _amount,
                _openClaim
            );
        vm.stopPrank();

        assertTrue(
            _vestingEscrow != address(0x0),
            "invalid vesting contract deployed"
        );
        assertTrue(llTokens > 0, "invalid tokens locked");
    }
}
