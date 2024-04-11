// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {VyperDeployer} from "./VyperDeployer.sol";
import {IVestingEscrowFactory} from "./IVestingEscrowFactory.sol";
import {IVestingEscrow} from "./IVestingEscrow.sol";
import {IVestingEscrowDepositor} from "./IVestingEscrowDepositor.sol";
import {IStakingRewards} from "./IStakingRewards.sol";
import {ILiquidLocker} from "./ILiquidLocker.sol";
import {IVeYFI} from "./IVeYFI.sol";
import {IProxy} from "./IProxy.sol";
import {IDYFIRewardPool} from "./IDYFIRewardPool.sol";
import {IMockToken} from "../mocks/IMockToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

abstract contract BaseTest is Test {
    address public constant GOV = address(0xBEEF);
    address public constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address public constant VEYFI = 0x90c1f9220d90d3966FbeE24045EDd73E1d588aD5;
    address public constant DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;

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

    function _deployVestingEscrowFactory(address _deployer, address yfi, address owner) internal returns (IVestingEscrowFactory) {
        IVestingEscrow _target = _deployVestingEscrowTarget(_deployer);
        IVestingEscrowFactory _escrowFactory = _deployVestingEscrowFactory(_deployer, address(_target), yfi, owner);
        return _escrowFactory;
    }

    function _deployVestingEscrowFactory(
        address _deployer,
        address _target,
        address yfi,
        address owner
    ) internal returns (IVestingEscrowFactory) {
        vm.startPrank(_deployer);
        address _instance = deployer.deployContract(
            "contracts/vesting/",
            "VestingEscrowFactory",
            abi.encode(_target, yfi, owner)
        );
        vm.stopPrank();
        return IVestingEscrowFactory(_instance);
    }

    function _deployVestingEscrowDepositor(
        address _deployer,
        address yfi,
        address llToken,
        address staking,
        address owner
    ) internal returns (IVestingEscrowDepositor) {
        vm.startPrank(_deployer);
        address _instance = deployer.deployContract(
            "contracts/vesting/",
            "VestingEscrowDepositor",
            abi.encode(yfi, llToken, staking, owner)
        );
        vm.stopPrank();
        vm.label(_instance, "escrowDepositor");
        return IVestingEscrowDepositor(_instance);
    }

    function _deployStakingAndRewards(
        address _deployer,
        ILiquidLocker _liquidLocker,
        IProxy _proxy,
        IERC20 _lockingToken,
        IERC20 _discountToken
    ) internal returns (IERC4626 staking, IStakingRewards rewards) {
        vm.startPrank(_deployer);
        address _staking = deployer.deployContract(
            "contracts/",
            "Staking",
            abi.encode(address(_liquidLocker))
        );
        address _rewards = deployer.deployContract(
            "contracts/",
            "StakingRewards",
            abi.encode(address(_proxy), address(_staking), address(_lockingToken), address(_discountToken))
        );
        vm.stopPrank();
        return (IERC4626(_staking), IStakingRewards(_rewards));
    }

    function _deployVeYFI(address _deployer, address token) internal returns (address) {
        address rewardPool = address(0); // Set in deployYFIRewardPool

        vm.startPrank(_deployer);
        address veYFI = deployer.deployContract("test/mocks/", "veYFI", abi.encode(token, rewardPool));
        vm.label(veYFI, "veYFI");
        vm.stopPrank();
        return veYFI;
    }

    function _deployProxy(address _deployer, address _veToken) internal returns (IProxy) {

        vm.startPrank(_deployer);
        address proxy = deployer.deployContract("contracts/", "Proxy", abi.encode(_veToken));
        vm.label(proxy, "proxy");
        vm.stopPrank();
        return IProxy(proxy);
    }

    function deployYFIRewardPool(address _deployer, address veYFI, uint256 startTime) internal returns (address) {
        vm.startPrank(_deployer);
        address rewardPool = deployer.deployContract("test/mocks/", "YFIRewardPool", abi.encode(veYFI, startTime));
        vm.label(rewardPool, "yfiRewardPool");
        IVeYFI(veYFI).setRewardPool(rewardPool);
        vm.stopPrank();
        return rewardPool;
    }

    function deployDYFIRewardPool(
        address _deployer,
        address veYFI,
        address dYFI,
        uint256 startTime
    ) internal returns (address) {
        vm.startPrank(_deployer);
        address rewardPool = deployer.deployContract(
            "test/mocks/",
            "dYFIRewardPool",
            abi.encode(veYFI, dYFI, startTime)
        );
        vm.label(rewardPool, "dYfiRewardPool");
        vm.stopPrank();
        return rewardPool;
    }

    function _deployveYFIContext(address _deployer) internal returns (address token, address dYfi, address votingEscrow, address dYfiRewardPool) {
        vm.etch(YFI, address(_deployToken(_deployer)).code);
        vm.etch(DYFI, address(_deployToken(_deployer)).code);

        address veYFI = _deployVeYFI(GOV, YFI);
        vm.etch(VEYFI, address(veYFI).code);

        uint256 startTime = block.timestamp;
        IDYFIRewardPool dYFIRewardPool = IDYFIRewardPool(deployDYFIRewardPool(GOV, veYFI, address(DYFI), startTime));

        return (YFI, DYFI, veYFI, address(dYFIRewardPool));
    }

    function _deployLiquidLocker(
        address _deployer,
        address _proxy
    ) internal returns (ILiquidLocker) {
        (address token, , address votingEscrow,) = _deployveYFIContext(_deployer);

        vm.startPrank(_deployer);
        address _instance = deployer.deployContract(
            "contracts/",
            "LiquidLocker",
            abi.encode(token, votingEscrow, _proxy)
        );
        vm.stopPrank();
        return ILiquidLocker(_instance);
    }

    function _deployLiquidLocker(
        address _deployer
    ) internal returns (ILiquidLocker, IMockToken, IVeYFI, IProxy, IERC4626, IStakingRewards) {
        (address token, address dYFI, address votingEscrow,) = _deployveYFIContext(_deployer);

        address _proxy = address(_deployProxy(_deployer, votingEscrow));

        vm.startPrank(_deployer);
        address _instance = deployer.deployContract(
            "contracts/",
            "LiquidLocker",
            abi.encode(token, votingEscrow, _proxy)
        );
        vm.stopPrank();

        vm.startPrank(IProxy(_proxy).management());
        IProxy(_proxy).set_operator(_instance, true);
        vm.stopPrank();

        (IERC4626 staking, IStakingRewards rewards) = _deployStakingAndRewards(
            _deployer,
            ILiquidLocker(_instance),
            IProxy(_proxy),
            IERC20(token),
            IERC20(dYFI)
        );

        return (
            ILiquidLocker(_instance),
            IMockToken(token),
            IVeYFI(votingEscrow),
            IProxy(_proxy),
            staking,
            rewards
        );
    }

    function _deployVestingEscrowTarget(
        address _deployer
    ) internal returns (IVestingEscrow) {
        vm.startPrank(_deployer);
        IVestingEscrow _instance = IVestingEscrow(
            deployer.deployContract("contracts/vesting/", "VestingEscrowLL")
        );
        vm.stopPrank();
        return IVestingEscrow(_instance);
    }
}
