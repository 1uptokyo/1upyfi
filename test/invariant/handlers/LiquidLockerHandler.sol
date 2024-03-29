// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ILiquidLocker} from "../../utils/ILiquidLocker.sol";
import {IMockToken} from "../../mocks/IMockToken.sol";
import {IProxy} from "../../utils/IProxy.sol";
import {IVeYFI} from "../../utils/IVeYFI.sol";

contract LiquidLockerHandler is CommonBase, StdCheats, StdUtils {
    uint256 private constant SCALE = 69_420;
    uint256 private constant WEEK = 7 * 24 * 60 * 60;
    uint256 private constant LOCK_TIME = 500 * WEEK;

    ILiquidLocker private liquidLocker;
    IMockToken private token;
    IProxy private proxy;
    IVeYFI private veYFI;

    uint256 public depositedAmount;

    constructor(ILiquidLocker _liquidLocker) {
        liquidLocker = _liquidLocker;
        token = IMockToken(_liquidLocker.token());
        proxy = IProxy(_liquidLocker.proxy());
        veYFI = IVeYFI(_liquidLocker.voting_escrow());
    }

    function deposit(address _user, uint256 _amount) external {
        token.mint(_user, _amount);
        
        vm.startPrank(address(proxy));
        token.approve(address(veYFI), _amount);
        vm.stopPrank();

        vm.startPrank(_user);
        token.approve(address(liquidLocker), _amount);
        liquidLocker.deposit(_amount);
        vm.stopPrank();

        depositedAmount += _amount;
    }

    function mint(address _user, uint256 _amount) external {
        if (veYFI.locked(_user).amount == 0) {
            return;
        }

        token.mint(_user, _amount);

        vm.startPrank(address(proxy));
        token.approve(address(veYFI), _amount);
        vm.stopPrank();

        vm.startPrank(_user);
        token.approve(address(proxy), _amount);
        veYFI.modify_lock(_amount, 0, address(proxy));
        vm.stopPrank();

        liquidLocker.mint();

        depositedAmount += _amount;
    }

}
