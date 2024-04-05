# @version 0.3.10
"""
@title Gauge
@author 1up
@license GNU AGPLv3
@notice
    Vault with 1:1 of underlying Yearn gauge token.
    Does not store balances directly, instead they are reported
    to the reward contract.
    The underlying Yearn gauge tokens are held by the proxy.
"""

from vyper.interfaces import ERC20
from vyper.interfaces import ERC4626
implements: ERC20
implements: ERC4626

interface ERC20Detailed:
    def name() -> String[124]: view
    def symbol() -> String[61]: view
    def decimals() -> uint8: view

interface YearnGauge:
    def getReward(_account: address): nonpayable

interface Rewards:
    def report(_ygauge: address, _from: address, _to: address, _amount: uint256, _rewards: uint256): nonpayable
    def gauge_supply(_gauge: address) -> uint256: view
    def gauge_balance(_gauge: address, _account: address) -> uint256: view

asset: public(immutable(address))
ygauge: public(immutable(address))
proxy: public(immutable(address))
reward_token: public(immutable(ERC20))
rewards: public(immutable(Rewards))
allowance: public(HashMap[address, HashMap[address, uint256]])

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

event Deposit:
    sender: indexed(address)
    owner: indexed(address)
    assets: uint256
    shares: uint256

event Withdraw:
    sender: indexed(address)
    receiver: indexed(address)
    owner: indexed(address)
    assets: uint256
    shares: uint256

@external
def __init__(_ygauge: address, _proxy: address, _reward_token: address, _rewards: address):
    """
    @notice Constructor
    @param _ygauge Yearn gauge address
    @param _proxy Proxy
    @param _reward_token Reward token address
    @param _rewards Rewards contract
    """
    asset = ERC4626(_ygauge).asset()
    ygauge = _ygauge
    proxy = _proxy
    reward_token = ERC20(_reward_token)
    rewards = Rewards(_rewards)
    assert reward_token.approve(_rewards, max_value(uint256), default_return_value=True)
    assert ERC20(asset).approve(_ygauge, max_value(uint256), default_return_value=True)
    log Transfer(empty(address), msg.sender, 0)

@external
@view
def name() -> String[128]:
    """
    @notice Get the gauge name
    @return Gauge name
    @dev Based on the name of the asset inside the Yearn gauge
    """
    name: String[124] = ERC20Detailed(asset).name()
    return concat("1UP ", name)

@external
@view
def symbol() -> String[64]:
    """
    @notice Get the gauge symbol
    @return Gauge symbol
    @dev Based on the name of the asset inside the Yearn gauge
    """
    symbol: String[61] = ERC20Detailed(asset).symbol()
    return concat("up-", symbol)

@external
@view
def decimals() -> uint8:
    """
    @notice Get the gauge decimals
    @return Gauge decimals
    @dev Same as the decimals of the asset inside the Yearn gauge
    """
    return ERC20Detailed(asset).decimals()

@external
@view
def totalSupply() -> uint256:
    """
    @notice Get the gauge total supply
    @return Gauge total supply
    """
    return rewards.gauge_supply(self)

@external
@view
def balanceOf(_account: address) -> uint256:
    """
    @notice Get the gauge balance of a user
    @param _account User
    @return Gauge balance
    """
    return rewards.gauge_balance(self, _account)

@external
def transfer(_to: address, _value: uint256) -> bool:
    """
    @notice Transfer gauge tokens to another user
    @param _to User to transfer gauge tokens to
    @param _value Amount of gauge tokens to transfer
    @return Always True
    """
    assert _to != empty(address) and _to != self

    if _value > 0:
        rewards.report(ygauge, msg.sender, _to, _value, 0)

    log Transfer(msg.sender, _to, _value)
    return True

@external
def transferFrom(_from: address, _to: address, _value: uint256) -> bool:
    """
    @notice Transfer another user's gauge tokens by spending an allowance
    @param _from User to transfer gauge tokens from
    @param _to User to transfer gauge tokens to
    @param _value Amount of gauge tokens to transfer
    @return Always True
    """
    assert _to != empty(address) and _to != self

    if _value > 0:
        allowance: uint256 = self.allowance[_from][msg.sender]
        if allowance < max_value(uint256):
            self.allowance[_from][msg.sender] = allowance - _value

        rewards.report(ygauge, _from, _to, _value, 0)

    log Transfer(_from, _to, _value)
    return True

@external
def approve(_spender: address, _value: uint256) -> bool:
    """
    @notice Approve spending of the caller's gauge tokens
    @param _spender User that is allowed to spend caller's tokens
    @param _value Amount of tokens spender is allowed to spend
    @return Always True
    """
    assert _spender != empty(address)

    self.allowance[msg.sender][_spender] = _value
    log Approval(msg.sender, _spender, _value)
    return True

@view
@external
def totalAssets() -> uint256:
    """
    @notice Get the total amount of assets in the vault
    @return Total amount of assets
    """
    return rewards.gauge_supply(self)

@view
@external
def convertToShares(_assets: uint256) -> uint256:
    """
    @notice Convert an amount of assets to shares
    @param _assets Amount of assets
    @return Amount of shares
    """
    return _assets

@view
@external
def convertToAssets(_shares: uint256) -> uint256:
    """
    @notice Convert an amount of shares to assets
    @param _shares Amount of shares
    @return Amount of assets
    """
    return _shares

@view
@external
def maxDeposit(_owner: address) -> uint256:
    """
    @notice Get the maximum amount of assets a user can deposit
    @param _owner User depositing
    @return Maximum amount of assets that can be deposited
    """
    return max_value(uint256)

@view
@external
def previewDeposit(_assets: uint256) -> uint256:
    """
    @notice Preview a deposit
    @param _assets Amount of assets to be deposited
    @return Equivalent amount of shares to be minted
    """
    return _assets

@external
def deposit(_assets: uint256, _receiver: address = msg.sender) -> uint256:
    """
    @notice Deposit assets
    @param _assets Amount of assets to deposit
    @param _receiver Recipient of the shares
    @return Amount of shares minted
    """
    self._deposit(_assets, _receiver)
    return _assets

@view
@external
def maxMint(_owner: address) -> uint256:
    """
    @notice Get the maximum amount of shares a user can mint
    @param _owner User minting
    @return Maximum amount of shares that can be minted
    """
    return max_value(uint256)

@view
@external
def previewMint(_shares: uint256) -> uint256:
    """
    @notice Preview a mint
    @param _shares Amount of shares to be minted
    @return Equivalent amount of assets to be deposited
    """
    return _shares

@external
def mint(_shares: uint256, _receiver: address = msg.sender) -> uint256:
    """
    @notice Mint shares
    @param _shares Amount of shares to mint
    @param _receiver Recipient of the shares
    @return Amount of assets deposited
    """
    self._deposit(_shares, _receiver)
    return _shares

@view
@external
def maxWithdraw(_owner: address) -> uint256:
    """
    @notice Get the maximum amount of assets a user can withdraw
    @param _owner User withdrawing
    @return Maximum amount of assets that can be withdrawn
    """
    return rewards.gauge_balance(self, _owner)

@view
@external
def previewWithdraw(_assets: uint256) -> uint256:
    """
    @notice Preview a withdrawal
    @param _assets Amount of assets to be withdrawn
    @return Equivalent amount of shares to be burned
    """
    return _assets

@external
def withdraw(_assets: uint256, _receiver: address = msg.sender, _owner: address = msg.sender) -> uint256:
    """
    @notice Withdraw assets
    @param _assets Amount of assets to withdraw
    @param _receiver Recipient of the assets
    @param _owner Owner of the shares
    @return Amount of shares redeemed
    """
    self._withdraw(_assets, _receiver, _owner)
    return _assets

@view
@external
def maxRedeem(_owner: address) -> uint256:
    """
    @notice Get the maximum amount of shares a user can redeem
    @param _owner User redeeming
    @return Maximum amount of shares that can be redeemed
    """
    return rewards.gauge_balance(self, _owner)

@view
@external
def previewRedeem(_shares: uint256) -> uint256:
    """
    @notice Preview a redemption
    @param _shares Amount of shares to be redeemed
    @return Equivalent amount of assets to be withdrawn
    """
    return _shares

@external
def redeem(_shares: uint256, _receiver: address = msg.sender, _owner: address = msg.sender) -> uint256:
    """
    @notice Redeem shares
    @param _shares Amount of shares to redeem
    @param _receiver Recipient of the assets
    @param _owner Owner of the shares
    @return Amount of assets withdrawn
    """
    self._withdraw(_shares, _receiver, _owner)
    return _shares

@internal
def _deposit(_assets: uint256, _receiver: address):
    """
    @notice
        Handle a deposit by claiming rewards, reporting to the rewards contract
        and transferring tokens from the caller to the proxy
    """
    assert _assets > 0
    pending: uint256 = self._pending()
    rewards.report(ygauge, empty(address), _receiver, _assets, pending)
    assert ERC20(asset).transferFrom(msg.sender, self, _assets, default_return_value=True)
    ERC4626(ygauge).deposit(_assets, proxy)
    log Deposit(msg.sender, _receiver, _assets, _assets)
    log Transfer(empty(address), _receiver, _assets)

@internal
def _withdraw(_assets: uint256, _receiver: address, _owner: address):
    """
    @notice
        Handle a withdrawal by claiming rewards, reporting to the rewards contract
        and transferring tokens from the proxy to the receiver
    """
    assert _assets > 0
    assert _receiver != empty(address) and _receiver != self
    if _owner != msg.sender:
        allowance: uint256 = self.allowance[_owner][msg.sender]
        if allowance < max_value(uint256):
            self.allowance[_owner][msg.sender] = allowance - _assets
    pending: uint256 = self._pending()
    rewards.report(ygauge, _owner, empty(address), _assets, pending)
    ERC4626(ygauge).withdraw(_assets, _receiver, proxy)
    log Withdraw(msg.sender, _receiver, _owner, _assets, _assets)
    log Transfer(_owner, empty(address), _assets)

@internal
def _pending() -> uint256:
    """
    @notice Claim rewards from the Yearn gauge and return reward balance
    """
    YearnGauge(ygauge).getReward(proxy)
    return reward_token.balanceOf(self)
