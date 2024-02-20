# @version 0.3.10

from vyper.interfaces import ERC20
from vyper.interfaces import ERC4626
implements: ERC20
implements: ERC4626

interface YearnGauge:
    def getReward(_account: address): nonpayable

interface Collector:
    def report(_ygauge: address, _from: address, _to: address, _amount: uint256, _rewards: uint256): nonpayable
    def gauge_supply(_gauge: address) -> uint256: view
    def gauge_balance(_gauge: address, _account: address) -> uint256: view

asset: public(immutable(address))
proxy: public(immutable(address))
reward: public(immutable(ERC20))
collector: public(immutable(Collector))

allowance: public(HashMap[address, HashMap[address, uint256]])

event Transfer:
    _from: indexed(address)
    _to: indexed(address)
    _value: uint256

event Approval:
    _owner: indexed(address)
    _spender: indexed(address)
    _value: uint256

event Deposit:
    _sender: indexed(address)
    _owner: indexed(address)
    _assets: uint256
    _shares: uint256

event Withdraw:
    _sender: indexed(address)
    _receiver: indexed(address)
    _owner: indexed(address)
    _assets: uint256
    _shares: uint256

@external
def __init__(_asset: address, _proxy: address, _reward: address, _collector: address):
    asset = _asset
    proxy = _proxy
    reward = ERC20(_reward)
    collector = Collector(_collector)
    assert reward.approve(_collector, max_value(uint256), default_return_value=True)
    log Transfer(empty(address), msg.sender, 0)

@external
@view
def totalSupply() -> uint256:
    return collector.gauge_supply(self)

@external
@view
def balanceOf(_account: address) -> uint256:
    return collector.gauge_balance(self, _account)

@external
def transfer(_to: address, _value: uint256) -> bool:
    assert _to != empty(address) and _to != self
    assert _value > 0

    collector.report(asset, msg.sender, _to, _value, 0)
    log Transfer(msg.sender, _to, _value)
    return True

@external
def transferFrom(_from: address, _to: address, _value: uint256) -> bool:
    assert _to != empty(address) and _to != self
    assert _value > 0

    allowance: uint256 = self.allowance[_from][msg.sender] - _value
    self.allowance[_from][msg.sender] = allowance
    log Approval(_from, msg.sender, allowance)

    collector.report(asset, _from, _to, _value, 0)
    log Transfer(_from, _to, _value)
    return True

@external
def approve(_spender: address, _value: uint256) -> bool:
    assert _spender != empty(address)

    self.allowance[msg.sender][_spender] = _value
    log Approval(msg.sender, _spender, _value)
    return True

@view
@external
def totalAssets() -> uint256:
    return collector.gauge_supply(self)

@view
@external
def convertToShares(_assets: uint256) -> uint256:
    return _assets

@view
@external
def convertToAssets(_shares: uint256) -> uint256:
    return _shares

@view
@external
def maxDeposit(_owner: address) -> uint256:
    return max_value(uint256)

@view
@external
def previewDeposit(_assets: uint256) -> uint256:
    return _assets

@external
def deposit(_assets: uint256, _receiver: address = msg.sender) -> uint256:
    self._deposit(_assets, _receiver)
    return _assets

@view
@external
def maxMint(_owner: address) -> uint256:
    return max_value(uint256)

@view
@external
def previewMint(_shares: uint256) -> uint256:
    return _shares

@external
def mint(_shares: uint256, _receiver: address = msg.sender) -> uint256:
    self._deposit(_shares, _receiver)
    return _shares

@view
@external
def maxWithdraw(_owner: address) -> uint256:
    return collector.gauge_balance(self, _owner)

@view
@external
def previewWithdraw(_assets: uint256) -> uint256:
    return _assets

@external
def withdraw(_assets: uint256, _receiver: address = msg.sender, _owner: address = msg.sender) -> uint256:
    self._withdraw(_assets, _receiver, _owner)
    return _assets

@view
@external
def maxRedeem(_owner: address) -> uint256:
    return collector.gauge_balance(self, _owner)

@view
@external
def previewRedeem(_shares: uint256) -> uint256:
    return _shares

@external
def redeem(_shares: uint256, _receiver: address = msg.sender, _owner: address = msg.sender) -> uint256:
    self._withdraw(_shares, _receiver, _owner)
    return _shares

@external
def harvest() -> uint256:
    assert msg.sender == collector.address
    return self._harvest()

@internal
def _deposit(_assets: uint256, _receiver: address):
    rewards: uint256 = self._harvest()
    collector.report(asset, empty(address), _receiver, _assets, rewards)
    assert ERC20(asset).transferFrom(msg.sender, proxy, _assets, default_return_value=True)
    log Deposit(msg.sender, _receiver, _assets, _assets)
    log Transfer(empty(address), _receiver, _assets)

@internal
def _withdraw(_assets: uint256, _receiver: address, _owner: address):
    if _owner != msg.sender:
        allowance: uint256 = self.allowance[_owner][msg.sender] - _assets
        self.allowance[_owner][msg.sender] = allowance
        log Approval(_owner, msg.sender, allowance)
    rewards: uint256 = self._harvest()
    collector.report(asset, _owner, empty(address), _assets, rewards)
    assert ERC20(asset).transferFrom(proxy, msg.sender, _assets, default_return_value=True)
    log Withdraw(msg.sender, _receiver, _owner, _assets, _assets)
    log Transfer(_owner, empty(address), _assets)

@internal
def _harvest() -> uint256:
    YearnGauge(asset).getReward(proxy)
    return reward.balanceOf(self)
