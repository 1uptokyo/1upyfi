# @version 0.3.10

from vyper.interfaces import ERC20
from vyper.interfaces import ERC20Detailed

implements: ERC20
implements: ERC20Detailed

interface Proxy:
    def modify_lock(_amount: uint256, _unlock_time: uint256): nonpayable

interface YearnVotingEscrow:
    def locked(_account: address) -> uint256: view

token: public(immutable(ERC20))
voting_escrow: immutable(YearnVotingEscrow)
proxy: public(immutable(Proxy))

totalSupply: public(uint256)
balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])

decimals: public(constant(uint8)) = 18
name: public(constant(String[14])) = "1UP Locked YFI"
symbol: public(constant(String[5])) = "upYFI"

WEEK: constant(uint256) = 7 * 24 * 60 * 60
LOCK_TIME: constant(uint256) = 500 * WEEK

event Transfer:
    _from: indexed(address)
    _to: indexed(address)
    _value: uint256

event Approval:
    _owner: indexed(address)
    _spender: indexed(address)
    _value: uint256

@external
def __init__(_token: address, _voting_escrow: address, _proxy: address):
    token = ERC20(_token)
    voting_escrow = YearnVotingEscrow(_voting_escrow)
    proxy = Proxy(_proxy)
    log Transfer(empty(address), msg.sender, 0)

@external
def deposit(_amount: uint256, _receiver: address = msg.sender):
    self._mint(_amount, _receiver)
    assert token.transferFrom(msg.sender, proxy.address, _amount, default_return_value=True)
    proxy.modify_lock(_amount, block.timestamp + LOCK_TIME)

@external
def mint(_receiver: address = msg.sender) -> uint256:
    excess: uint256 = voting_escrow.locked(proxy.address) - self.totalSupply
    self._mint(excess, _receiver)
    return excess

@internal
def _mint(_amount: uint256, _receiver: address):
    assert _amount > 0
    assert _receiver != empty(address)
    self.totalSupply += _amount
    self.balanceOf[_receiver] += _amount
    log Transfer(empty(address), _receiver, _amount)

@external
def extend_lock():
    proxy.modify_lock(0, block.timestamp + LOCK_TIME)

@external
def transfer(_to: address, _value: uint256) -> bool:
    assert _to != empty(address) and _to != self
    assert _value > 0

    self.balanceOf[msg.sender] -= _value
    self.balanceOf[_to] += _value
    log Transfer(msg.sender, _to, _value)
    return True

@external
def transferFrom(_from: address, _to: address, _value: uint256) -> bool:
    assert _to != empty(address) and _to != self
    assert _value > 0

    allowance: uint256 = self.allowance[_from][msg.sender] - _value
    self.allowance[_from][msg.sender] = allowance
    log Approval(_from, msg.sender, allowance)

    self.balanceOf[_from] -= _value
    self.balanceOf[_to] += _value
    log Transfer(_from, _to, _value)
    return True

@external
def approve(_spender: address, _value: uint256) -> bool:
    assert _spender != empty(address)

    self.allowance[msg.sender][_spender] = _value
    log Approval(msg.sender, _spender, _value)
    return True
