# @version 0.3.10

from vyper.interfaces import ERC20
from vyper.interfaces import ERC4626
implements: ERC20
implements: ERC4626

asset: public(immutable(address))
totalSupply: public(uint256)
balanceOf: public(HashMap[address, uint256])
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
def __init__(_asset: address):
    asset = _asset

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

@view
@external
def totalAssets() -> uint256:
    return self.totalSupply

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
    return self.balanceOf[_owner]

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
    return self.balanceOf[_owner]

@view
@external
def previewRedeem(_shares: uint256) -> uint256:
    return _shares

@external
def redeem(_shares: uint256, _receiver: address = msg.sender, _owner: address = msg.sender) -> uint256:
    self._withdraw(_shares, _receiver, _owner)
    return _shares

@internal
def _deposit(_assets: uint256, _receiver: address):
    self.totalSupply += _assets
    self.balanceOf[_receiver] += _assets

    assert ERC20(asset).transferFrom(msg.sender, self, _assets, default_return_value=True)
    log Deposit(msg.sender, _receiver, _assets, _assets)
    log Transfer(empty(address), _receiver, _assets)

@internal
def _withdraw(_assets: uint256, _receiver: address, _owner: address):
    if _owner != msg.sender:
        allowance: uint256 = self.allowance[_owner][msg.sender] - _assets
        self.allowance[_owner][msg.sender] = allowance
        log Approval(_owner, msg.sender, allowance)

    self.totalSupply -= _assets
    self.balanceOf[_owner] -= _assets

    assert ERC20(asset).transferFrom(self, msg.sender, _assets, default_return_value=True)
    log Withdraw(msg.sender, _receiver, _owner, _assets, _assets)
    log Transfer(_owner, empty(address), _assets)
