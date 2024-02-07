# @version 0.3.10

interface Locker:
    def modify_lock(_amount: uint256, _unlock_time: uint256): nonpayable

implements: Locker

locker: immutable(address)
owner: public(address)
reverse_proxy: public(address)
operators: public(HashMap[address, bool])

MAX_SIZE: constant(uint256) = 1024

@external
def __init__(_locker: address):
    locker = _locker
    self.owner = msg.sender
    self.operators[msg.sender] = True

@external
@payable
def __default__() -> Bytes[MAX_SIZE]:
    reverse: address = self.reverse_proxy
    assert reverse != empty(address)
    return raw_call(reverse, msg.data, max_outsize=MAX_SIZE, value=msg.value)

@external
@payable
def call(_target: address, _data: Bytes[MAX_SIZE]) -> Bytes[MAX_SIZE]:
    assert self.operators[msg.sender]
    return raw_call(_target, _data, max_outsize=MAX_SIZE, value=msg.value)

@external
def modify_lock(_amount: uint256, _unlock_time: uint256):
    assert self.operators[msg.sender]
    Locker(locker).modify_lock(_amount, _unlock_time)

@external
def set_operator(_operator: address, _flag: bool):
    assert msg.sender == self.owner
    self.operators[_operator] = _flag

@external
def set_owner(_owner: address):
    assert msg.sender == self.owner
    self.owner = _owner
