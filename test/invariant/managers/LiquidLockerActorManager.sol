// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console2 as console} from "forge-std/console2.sol";
import {LiquidLockerHandler} from "../handlers/LiquidLockerHandler.sol";

contract LiquidLockerActorManager is CommonBase, StdCheats, StdUtils {

    uint256 public constant MIN_YFI_AMOUNT = 1e18;
    uint256 public constant MAX_YFI_AMOUNT = 36666e18;
    LiquidLockerHandler[] private handlers;
    uint256 private maxSkipSeconds;

    constructor(
        LiquidLockerHandler[] memory _handlers,
        uint256 _maxSkipSeconds
    ) {
        handlers = _handlers;
        maxSkipSeconds = _maxSkipSeconds;
    }

    function skipSeconds(uint256 _seconds) external returns (uint256) {
        _seconds = bound(_seconds, 1, maxSkipSeconds);
        skip(_seconds);
        return block.timestamp;
    }

    function skipDays(uint256 _days) external returns (uint256) {
        _days = bound(_days, 1, type(uint16).max);
        uint256 _seconds = bound(_days * 86_400, 1, maxSkipSeconds);
        skip(_seconds);
        return block.timestamp;
    }

    function deposit(
        uint256 _handlerIndex,
        address _user,
        uint256 _amount
    ) external {
        vm.assume(_user != address(0x0));
        uint256 index = bound(_handlerIndex, 0, handlers.length - 1);
        _amount = bound(_amount, MIN_YFI_AMOUNT, MAX_YFI_AMOUNT);
        handlers[index].deposit(_user, _amount);
    }

    function mint(
        uint256 _handlerIndex,
        address _user,
        uint256 _amount
    ) external {
        vm.assume(_user != address(0x0));
        uint256 index = bound(_handlerIndex, 0, handlers.length - 1);
        _amount = bound(_amount, MIN_YFI_AMOUNT, MAX_YFI_AMOUNT);
        handlers[index].mint(_user, _amount);
    }

    function depositedAmount(
        uint256 _handlerIndex
    ) external view returns (uint256) {
        uint256 index = bound(_handlerIndex, 0, handlers.length - 1);
        return handlers[index].depositedAmount();
    }

    function totalDepositedAmount() external view returns (uint256) {
        uint256 _totalDepositedAmount;
        uint256 totalHandlers = handlers.length;
        for (uint256 i = 0; i < totalHandlers; ++i) {
            _totalDepositedAmount += handlers[i].depositedAmount();
        }
        return _totalDepositedAmount;
    }
}
