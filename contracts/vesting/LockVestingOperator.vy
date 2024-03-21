# @version 0.3.10
"""
@title Lock vesting operator
@author 1UP
@license GNU AGPLv3
@notice
    Allows recipients of vests to lock their staked upYFI to receive the 
    maximum vote weight possible right away, instead of having to wait for
    it to accrue over time
"""

interface Vesting:
    def owner() -> address: view
    def recipient() -> address: view
    def call(_target: address, _data: Bytes[2048]): nonpayable

staking: public(immutable(address))

@external
def __init__(_staking: address):
    staking = _staking

@external
def lock(_vesting: Vesting, _duration: uint256):
    assert msg.sender == _vesting.recipient() or msg.sender == _vesting.owner()
    data: Bytes[36] = _abi_encode(_duration, method_id=method_id("lock(uint256)"))
    _vesting.call(staking, data)
