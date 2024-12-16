# pragma version 0.3.10
# pragma optimize gas
# pragma evm-version cancun
"""
@title Zap
@author 1up
@license GNU AGPLv3
@notice
    Allow users to deposit or withdraw into 1UP using the underlying asset directly
"""

from vyper.interfaces import ERC20
from vyper.interfaces import ERC4626

interface WETH:
    def deposit(): payable
    def withdraw(_amount: uint256): nonpayable

interface YearnVault:
    def redeem(_shares: uint256, _recipient: address, _owner: address, _max_loss: uint256) -> uint256: nonpayable

interface LegacyYearnVault:
    def token() -> address: view
    def withdraw(_shares: uint256, _recipient: address, _max_loss: uint256) -> uint256: nonpayable

weth: public(immutable(WETH))
management: public(address)

@external
def __init__(_weth: address):
    weth = WETH(_weth)
    self.management = msg.sender

@external
@payable
def __default__():
    assert msg.sender == weth.address

@external
def deposit(_gauge: address, _assets: uint256) -> uint256:
    yvault: address = ERC4626(_gauge).asset()
    underlying: address = ERC4626(yvault).asset()

    assert ERC20(underlying).transferFrom(msg.sender, self, _assets, default_return_value=True)
    return self._deposit(_gauge, yvault, underlying, _assets)

@external
@payable
def deposit_eth(_gauge: address) -> uint256:
    yvault: address = ERC4626(_gauge).asset()
    underlying: address = ERC4626(yvault).asset()
    assert underlying == weth.address, "not WETH"

    weth.deposit(value=msg.value)
    return self._deposit(_gauge, yvault, weth.address, msg.value)

@external
def deposit_legacy(_gauge: address, _assets: uint256) -> uint256:
    yvault: address = ERC4626(_gauge).asset()
    underlying: address = LegacyYearnVault(yvault).token()

    assert ERC20(underlying).transferFrom(msg.sender, self, _assets, default_return_value=True)
    return self._deposit(_gauge, yvault, underlying, _assets)

@external
def withdraw(_gauge: address, _shares: uint256, _max_loss: uint256 = 0) -> uint256:
    yvault: address = ERC4626(_gauge).asset()
    return self._withdraw(_gauge, yvault, _shares, _max_loss, msg.sender)

@external
def withdraw_eth(_gauge: address, _shares: uint256, _max_loss: uint256 = 0) -> uint256:
    yvault: address = ERC4626(_gauge).asset()
    underlying: address = ERC4626(yvault).asset()
    assert underlying == weth.address, "not WETH"

    assets: uint256 = self._withdraw(_gauge, yvault, _shares, _max_loss, self)
    weth.withdraw(assets)
    raw_call(msg.sender, b"", value=assets)
    return assets

@external
def withdraw_legacy(_gauge: address, _shares: uint256, _max_loss: uint256 = 0) -> uint256:
    yvault: address = ERC4626(_gauge).asset()

    # withdraw yvault token from 1up gauge
    ERC4626(_gauge).withdraw(_shares, self, msg.sender)

    # withdraw underlying token from yvault
    return LegacyYearnVault(yvault).withdraw(_shares, msg.sender, _max_loss)

@external
def rescue(_token: address, _amount: uint256 = max_value(uint256)):
    assert msg.sender == self.management

    if _token == empty(address):
        raw_call(msg.sender, b"", value=_amount)
        return

    amount: uint256 = _amount
    if _amount == max_value(uint256):
        amount = ERC20(_token).balanceOf(self)

    assert ERC20(_token).transfer(msg.sender, amount, default_return_value=True)

@external
def set_management(_management: address):
    assert msg.sender == self.management
    self.management = _management

@internal
def _deposit(_gauge: address, _yvault: address, _underlying: address, _assets: uint256) -> uint256:
    # deposit underlying token into yvault
    assert ERC20(_underlying).approve(_yvault, _assets, default_return_value=True)
    shares: uint256 = ERC4626(_yvault).deposit(_assets, self)

    # deposit yvault token into 1up gauge
    assert ERC20(_yvault).approve(_gauge, shares, default_return_value=True)
    ERC4626(_gauge).deposit(shares, msg.sender)

    return shares

@internal
def _withdraw(_gauge: address, _yvault: address, _shares: uint256, _max_loss: uint256, _recipient: address) -> uint256:
    # withdraw yvault token from 1up gauge
    ERC4626(_gauge).withdraw(_shares, self, msg.sender)

    # withdraw underlying token from yvault
    return YearnVault(_yvault).redeem(_shares, _recipient, self, _max_loss)
