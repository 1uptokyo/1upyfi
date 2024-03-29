// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {console2} from "forge-std/Test.sol";
import {ILiquidLocker} from "../utils/ILiquidLocker.sol";
import {IMockToken} from "../mocks/IMockToken.sol";
import {MockProxy} from "../mocks/MockProxy.sol";
import {BaseTest} from "../utils/Base.t.sol";

contract LiquidLockerTest is BaseTest {

    uint256 constant SCALE = 69_420;
    uint256 constant WEEK = 7 * 24 * 60 * 60;
    uint256 constant LOCK_TIME = 500 * WEEK;


    ILiquidLocker public liquidLocker;
    IMockToken public token;
    address public owner;
    address public proxy;

    function setUp() public {
        owner = address(0x3);
        proxy = address(new MockProxy());

        liquidLocker = _deployLiquidLocker(owner, proxy);
        token = IMockToken(liquidLocker.token());

        vm.label(owner, "owner");
        vm.label(address(liquidLocker), "liquidLocker");
        vm.label(address(token), "token");
        vm.label(proxy, "proxy");
    }

    function test_deposit(address _user, uint256 _amount) public {
        vm.assume(_user != address(0x0));
        vm.assume(_user != address(liquidLocker));
        vm.assume(_amount > 0);
        vm.assume(_amount < type(uint256).max / SCALE);

        token.mint(_user, _amount);
        vm.startPrank(_user);
        
        token.approve(address(liquidLocker), _amount);
        liquidLocker.deposit(_amount);
        vm.stopPrank();

        assertEq(token.balanceOf(proxy) * SCALE, liquidLocker.balanceOf(_user), "invalid token & liquid locker balance");
        assertEq(liquidLocker.totalSupply(), liquidLocker.balanceOf(_user), "invalid total supply & liquid locker balance");
    }
}
