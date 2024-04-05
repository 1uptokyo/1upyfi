# @version 0.3.10
"""
@title 1UP Vesting operator
@author 1UP
@license GNU AGPLv3
@notice
    Intended to be used as operator for supYFI vests inside the `VestingEscrowFactory`.
    Allows recipients of vests to:
    - Lock their staked upYFI to receive the maximum vote weight possible 
        right away, instead of having to wait for it to accrue over time
    - Claim staking rewards
"""

interface Vesting:
    def owner() -> address: view
    def recipient() -> address: view
    def call(_target: address, _data: Bytes[2048]): payable

staking: public(immutable(address))
rewards: public(immutable(address))

event Lock:
    vesting: indexed(Vesting)
    duration: uint256

event Claim:
    vesting: indexed(Vesting)
    receiver: address

@external
def __init__(_staking: address, _rewards: address):
    """
    @notice Constructor
    @param _staking supYFI address
    @param _rewards Staking rewards contract address
    """
    staking = _staking
    rewards = _rewards

@external
def lock(_vesting: Vesting, _duration: uint256 = max_value(uint256)):
    """
    @notice Lock vesting supYFI to increase its voting weight
    @param _vesting Vesting contract address
    @param _duration Lock duration (seconds)
    @dev Can only be called by recipient of the vest
    """
    assert msg.sender == _vesting.recipient()
    data: Bytes[36] = _abi_encode(_duration, method_id=method_id("lock(uint256)"))
    _vesting.call(staking, data)
    log Lock(_vesting, _duration)

@external
@payable
def claim(_vesting: Vesting, _receiver: address = msg.sender, _redeem_data: Bytes[256] = b""):
    """
    @notice Claim staking rewards from vesting supYFI
    @param _vesting Vesting contract address
    @param _receiver Reward recipient
    @param _redeem_data Data sent to redemption contract
    """
    assert msg.sender == _vesting.recipient()
    data: Bytes[356] = _abi_encode(_receiver, _redeem_data, method_id=method_id("claim(address,bytes)"))
    _vesting.call(rewards, data, value=msg.value)
    log Claim(_vesting, _receiver)
