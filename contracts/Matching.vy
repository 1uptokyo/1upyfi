# @version 0.3.10
"""
@title YFI matching
@author 1up
@license GNU AGPLv3
@notice
    Matches locked YFI at a predefinied rate.
    Anyone can transfer YFI into this contract.
    Recipient can claim the matched amount as supYFI.
    Owner can clawback any unmatched tokens.
"""

from vyper.interfaces import ERC20
from vyper.interfaces import ERC4626

interface LiquidLocker:
    def token() -> address: view
    def voting_escrow() -> address: view
    def proxy() -> address: view
    def deposit(_amount: uint256) -> uint256: nonpayable

interface YearnVotingEscrow:
    def locked(_account: address) -> uint256: view

staking: public(immutable(ERC4626))
liquid_locker: public(immutable(LiquidLocker))
proxy: public(immutable(address))
voting_escrow: public(immutable(YearnVotingEscrow))
owner: public(immutable(address))
recipient: public(immutable(address))
matching_rate: public(immutable(uint256))
matched: public(uint256)

MATCHING_SCALE: constant(uint256) = 10_000

@external
def __init__(_staking: address, _owner: address, _recipient: address, _matching_rate: uint256):
    """
    @notice Constructor
    @param _staking Staking contract address
    @param _owner Matching contract owner
    @param _recipient Matching recipient
    @param _matching_rate Matching rate (bps)
    """
    staking = ERC4626(_staking)
    liquid_locker = LiquidLocker(staking.asset())
    proxy = liquid_locker.proxy()
    voting_escrow = YearnVotingEscrow(liquid_locker.voting_escrow())
    owner = _owner
    recipient = _recipient
    matching_rate = _matching_rate

    assert ERC20(liquid_locker.token()).approve(liquid_locker.address, max_value(uint256), default_return_value=True)
    assert ERC20(liquid_locker.address).approve(_staking, max_value(uint256), default_return_value=True)

@external
def match() -> (uint256, uint256):
    """
    @notice Matches any additional locked YFI since last call
    @return Tuple with newly matched YFI amount, newly matched supYFI amount
    @dev Can only be called by matching recipient
    """
    assert msg.sender == recipient
    matched: uint256 = self.matched
    # amount locked, excluding what is previously matched by this contract
    locked: uint256 = voting_escrow.locked(proxy) - matched
    # amount to newly match
    match: uint256 = locked * matching_rate / MATCHING_SCALE - matched
    assert match > 0
    self.matched = matched + match

    ll_match: uint256 = liquid_locker.deposit(match)
    staking.deposit(ll_match, recipient)

    return match, ll_match

@external
def revoke(_token: address, _amount: uint256):
    """
    @notice Send tokens back to the owner
    @param _token Token address
    @param _amount Amount of tokens to revoke
    @dev Can only be called by owner
    """
    assert msg.sender == owner
    assert ERC20(_token).transfer(owner, _amount, default_return_value=True)
