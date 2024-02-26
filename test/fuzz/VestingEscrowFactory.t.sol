// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {console2} from "forge-std/Test.sol";
import {IVestingEscrow} from "../utils/IVestingEscrow.sol";
import {IVestingEscrowFactory} from "../utils/IVestingEscrowFactory.sol";
import {IMockToken} from "../mocks/IMockToken.sol";
import {BaseTest} from "../utils/Base.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VestingEscrowFactoryTest is BaseTest {
    IVestingEscrowFactory public escrowFactory;
    IMockToken public token;
    address public owner;

    function setUp() public {
        owner = address(0x3);
        token = _deployToken(owner);

        IVestingEscrow _target = _deployVestingEscrowTarget(owner);
        escrowFactory = _deployVestingEscrowFactory(owner, address(_target));

        vm.label(owner, "owner");
        vm.label(address(escrowFactory), "escrowFactory");
        vm.label(address(token), "token");
        vm.label(address(_target), "target");
    }

    function test_deploy_vesting_contract_valid(
        address _recipient,
        uint256 _amount,
        uint256 _vestingDuration,
        uint256 _vestingStart,
        uint256 _cliffLength,
        bool _openClaim,
        address _owner
    ) public {
        vm.assume(_recipient != address(0x0) && _recipient != address(this) && _recipient != address(token) && _recipient != owner);
        vm.assume(_amount > 0);
        vm.assume(_vestingDuration > 0);
        vm.assume(_cliffLength <= _vestingDuration);
        vm.assume(_vestingStart <= type(uint256).max - _vestingDuration);
        vm.assume(_vestingStart > block.timestamp);
        vm.assume(_owner != address(0x0));

        token.mint(_owner, _amount);
        vm.startPrank(_owner);
        token.approve(address(escrowFactory), _amount);
        address _vestingEscrow = escrowFactory.deploy_vesting_contract(
            address(token),
            _recipient,
            _amount,
            _vestingDuration,
            _vestingStart,
            _cliffLength,
            _openClaim,
            _owner
        );
        vm.stopPrank();

        assertTrue(_vestingEscrow != address(0x0), "invalid vesting contract deployed");
    }
}
