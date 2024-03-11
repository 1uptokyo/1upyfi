# @version 0.3.10

from vyper.interfaces import ERC20
implements: ERC20

interface Rewards:
    def report(_account: address, _balance: uint256): nonpayable

rewards: Rewards

totalSupply: public(uint256)
balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])

name: public(constant(String[11])) = "MockStaking"
symbol: public(constant(String[4])) = "MoSt"
decimals: public(constant(uint8)) = 18

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

@external
def __init__():
    log Transfer(empty(address), msg.sender, 0)

@external
def transfer(_to: address, _value: uint256) -> bool:
    assert _to != empty(address)
    self.rewards.report(msg.sender, self.balanceOf[msg.sender])
    self.rewards.report(_to, self.balanceOf[_to])

    self.balanceOf[msg.sender] -= _value
    self.balanceOf[_to] += _value
    log Transfer(msg.sender, _to, _value)
    return True

@external
def transferFrom(_from: address, _to: address, _value: uint256) -> bool:
    assert _to != empty(address)
    self.rewards.report(_from, self.balanceOf[_from])
    self.rewards.report(_to, self.balanceOf[_to])

    self.allowance[_from][msg.sender] -= _value
    self.balanceOf[_from] -= _value
    self.balanceOf[_to] += _value
    log Transfer(_from, _to, _value)
    return True

@external
def approve(_spender: address, _value: uint256) -> bool:
    self.allowance[msg.sender][_spender] = _value
    log Approval(msg.sender, _spender, _value)
    return True

@external
def mint(_account: address, _value: uint256):
    self.rewards.report(_account, self.balanceOf[_account])

    self.totalSupply += _value
    self.balanceOf[_account] += _value
    log Transfer(empty(address), _account, _value)

@external
def burn(_account: address, _value: uint256):
    self.rewards.report(_account, self.balanceOf[_account])

    self.totalSupply -= _value
    self.balanceOf[_account] -= _value
    log Transfer(_account, empty(address), _value)

@external
def set_rewards(_rewards: address):
    self.rewards = Rewards(_rewards)