// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVestingEscrow {

    function recipient() external view returns (address);
    function token() external view returns (IERC20);
    function start_time() external view returns (uint256);
    function end_time() external view returns (uint256);
    function cliff_length() external view returns (uint256);
    function total_locked() external view returns (uint256);
    function total_claimed() external view returns (uint256);
    function disabled_at() external view returns (uint256);
    function open_claim() external view returns (bool);
    function initialized() external view returns (bool);
    function owner() external view returns (address);

    function initialize(
        address _owner,
        IERC20 _token,
        address _recipient,
        uint256 _amount,
        uint256 _start_time,
        uint256 _end_time,
        uint256 _cliff_length,
        bool _open_claim
    ) external returns (bool);


    function unclaimed() external view returns (uint256);


    function locked() external view returns (uint256);


    function claim() external returns (uint256);
    function claim(address _beneficiary) external returns (uint256);
    function claim(address _beneficiary, uint256 _amount) external returns (uint256);
        


    function revoke() external;
    function revoke(uint256 _ts) external;
    function revoke(uint256 _ts, address _beneficiary) external;

    function disown() external;
    function set_open_claim(bool _open_claim) external;


    function collect_dust(IERC20 _token, address _beneficiary) external;
    function collect_dust(IERC20 _token) external;
}
