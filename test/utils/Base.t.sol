// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {VyperDeployer} from "./VyperDeployer.sol";
import {IVestingEscrowFactory} from "./IVestingEscrowFactory.sol";
import {IVestingEscrow} from "./IVestingEscrow.sol";
import {IMockToken} from "../mocks/IMockToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract BaseTest is Test {
    VyperDeployer internal deployer = new VyperDeployer();

    function _deployToken(address _deployer) internal returns (IMockToken) {
        vm.startPrank(_deployer);
        address _instance = deployer.deployContract(
            "contracts/mocks/",
            "MockToken"
        );
        vm.stopPrank();
        return IMockToken(_instance);
    }

    function _deployVestingEscrowFactory(address _deployer) internal returns (IVestingEscrowFactory) {
        IVestingEscrow _target = _deployVestingEscrowTarget(_deployer);
        IVestingEscrowFactory _escrowFactory = _deployVestingEscrowFactory(_deployer, address(_target));
        return _escrowFactory;
    }

    function _deployVestingEscrowFactory(
        address _deployer,
        address _target
    ) internal returns (IVestingEscrowFactory) {
        vm.startPrank(_deployer);
        address _instance = deployer.deployContract(
            "contracts/vesting/",
            "VestingEscrowFactory",
            abi.encode(_target)
        );
        vm.stopPrank();
        return IVestingEscrowFactory(_instance);
    }

    function _deployVestingEscrowTarget(
        address _deployer
    ) internal returns (IVestingEscrow) {
        vm.startPrank(_deployer);
        IVestingEscrow _instance = IVestingEscrow(
            deployer.deployContract("contracts/vesting/", "VestingEscrowSimple")
        );
        vm.stopPrank();
        return IVestingEscrow(_instance);
    }
}
