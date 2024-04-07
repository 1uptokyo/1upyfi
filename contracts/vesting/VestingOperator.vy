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
delegate_registry: public(immutable(address))
delegation_space: public(immutable(bytes32))

event Lock:
    vesting: indexed(Vesting)
    duration: uint256

event Claim:
    vesting: indexed(Vesting)
    receiver: address

@external
def __init__(_staking: address, _rewards: address, _delegate_registry: address, _delegation_space: bytes32):
    """
    @notice Constructor
    @param _staking supYFI address
    @param _rewards Staking rewards contract address
    @param _delegate_registry Snapshot delegate registry
    @param _delegation_space Snapshot delegation space
    """
    staking = _staking
    rewards = _rewards
    delegate_registry = _delegate_registry
    delegation_space = _delegation_space

@external
def set_snapshot_delegate(_vesting: Vesting, _delegate: address):
    """
    @notice Delegate vesting supYFI Snapshot voting weight
    @param _vesting Vesting contract address
    @param _delegate Address to delegate voting weight to
    """
    assert msg.sender == _vesting.recipient()
    data: Bytes[68] = b""
    if _delegate == empty(address):
        data = _abi_encode(delegation_space, method_id=method_id("clearDelegate(bytes32)"))
    else:
        data = _abi_encode(delegation_space, _delegate, method_id=method_id("setDelegate(bytes32,address)"))
    _vesting.call(delegate_registry, data)

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
