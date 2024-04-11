// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {console2} from "forge-std/Test.sol";
import {IVestingEscrow} from "../utils/IVestingEscrow.sol";
import {IVestingEscrowFactory} from "../utils/IVestingEscrowFactory.sol";
import {IVestingEscrowDepositor} from "../utils/IVestingEscrowDepositor.sol";
import {ILiquidLocker} from "../utils/ILiquidLocker.sol";
import {IStakingRewards} from "../utils/IStakingRewards.sol";
import {IVeYFI} from "../utils/IVeYFI.sol";
import {IProxy} from "../utils/IProxy.sol";
import {IMockToken} from "../mocks/IMockToken.sol";
import {BaseTest} from "../utils/Base.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract VestingEscrowFactoryTest is BaseTest {
    IVestingEscrowFactory public escrowFactory;
    // ILiquidLocker public liquidLocker;
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
            token, /* yfi */
            veYFI,
            proxy,
            staking,
            stakingRewards
        ) = _deployLiquidLocker(
            owner
        );

        escrowFactory = _deployVestingEscrowFactory(owner, address(_target), address(token), owner);

        vm.label(owner, "owner");
        vm.label(address(escrowFactory), "escrowFactory");
        vm.label(address(token), "token");
        vm.label(address(_target), "target");
        vm.label(address(liquidLocker), "liquidLocker");
        vm.label(address(staking), "staking");
        vm.label(address(proxy), "proxy");
    }

    function test_deploy_vesting_contract_valid(
        address _vestCreator,
        address _recipient,
        uint256 _amount,
        uint256 _vestingDuration,
        uint256 _vestingStart,
        uint256 _cliffLength,
        bool _openClaim,
        address _owner
    ) public {
        vm.assume(_vestCreator != address(0x0) && _vestCreator != address(this) && _vestCreator != address(token) && _vestCreator != owner && _vestCreator != _recipient);
        vm.assume(_recipient != address(0x0) && _recipient != address(this) && _recipient != address(token) && _recipient != owner);
        vm.assume(_amount > 1e18);
        vm.assume(_amount < type(uint64).max);
        vm.assume(_vestingDuration > 0);
        vm.assume(_cliffLength <= _vestingDuration);
        vm.assume(_vestingStart <= type(uint256).max - _vestingDuration);
        vm.assume(_vestingStart > block.timestamp);
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
        escrowFactory.set_liquid_locker(address(liquidLocker), address(_depositor));
        vm.stopPrank();

        vm.startPrank(address(liquidLocker));
        proxy.call(address(token), abi.encodeWithSelector(token.approve.selector, address(veYFI), type(uint256).max));
        vm.stopPrank();

        vm.startPrank(address(_depositor));
        token.approve(address(liquidLocker), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(address(_depositor));
        liquidLocker.approve(address(_depositor.staking()), type(uint256).max);
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
        (address _vestingEscrow, uint256 llTokens) = escrowFactory.deploy_vesting_contract(
            vestIdx,
            address(liquidLocker),
            _amount,
            _openClaim
        );
        vm.stopPrank();

        assertTrue(_vestingEscrow != address(0x0), "invalid vesting contract deployed");
        assertTrue(llTokens > 0, "invalid tokens locked");
    }
}
