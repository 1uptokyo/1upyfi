# @version 0.3.10
"""
@title Proxy
@author 1up
@license GNU AGPLv3
@notice
    Redeem discount token and lock into protocol's voting escrow.
    Redemption cost can be paid either by sending ETH or by selling some of the rewards.
"""

from vyper.interfaces import ERC20

interface Redeemer:
    def redeem(_account: address, _receiver: address, _lt_amount: uint256, _dt_amount: uint256, _data: Bytes[256]) -> uint256: payable
implements: Redeemer

interface VotingEscrow:
    def modify_lock(_amount: uint256, _unlock_time: uint256, _account: address): nonpayable

interface LiquidLocker:
    def token() -> address: view
    def mint(_receiver: address) -> uint256: nonpayable

interface YearnRedemption:
    def eth_required(amount: uint256) -> uint256: view
    def redeem(amount: uint256) -> uint256: payable

interface CurvePool:
    def exchange(
        _i: uint256, _j: uint256, _dx: uint256, _min_dy: uint256, _use_eth: bool
    ) -> uint256: nonpayable

voting_escrow: public(immutable(VotingEscrow))
liquid_locker: public(immutable(LiquidLocker))
locking_token: public(immutable(ERC20))
discount_token: public(immutable(ERC20))
proxy: public(immutable(address))
gauge_rewards: public(immutable(address))
staking_rewards: public(immutable(address))
management: public(address)
pending_management: public(address)
treasury: public(address)
yearn_redemption: public(YearnRedemption)
curve_pool: public(CurvePool)

event Redeem:
    account: indexed(address)
    receiver: address
    lt_amount: uint256
    dt_amount: uint256
    value: uint256
    minted: uint256

event ClaimExcess:
    excess: uint256

event SetTreasury:
    treasury: address

event SetYearnRedemption:
    yearn_redemption: address

event SetCurvePool:
    curve_pool: address

event PendingManagement:
    management: address

event SetManagement:
    management: address

SCALE: constant(uint256) = 69_420

@external
def __init__(
    _voting_escrow: address, _liquid_locker: address, _locking_token: address, _discount_token: address, 
    _proxy: address, _gauge_rewards: address, _staking_rewards: address,
):
    """
    @notice Constructor
    @param _voting_escrow Voting escrow
    @param _liquid_locker Liquid locker
    @param _locking_token Locking token
    @param _discount_token Discount token
    @param _proxy Proxy
    @param _gauge_rewards Gauge rewards contract
    @param _staking_rewards Staking rewards contract
    """
    voting_escrow = VotingEscrow(_voting_escrow)
    liquid_locker = LiquidLocker(_liquid_locker)
    locking_token = ERC20(_locking_token)
    discount_token = ERC20(_discount_token)
    proxy = _proxy
    gauge_rewards = _gauge_rewards
    staking_rewards = _staking_rewards
    self.management = msg.sender
    self.treasury = msg.sender
    assert locking_token.approve(_voting_escrow, max_value(uint256), default_return_value=True)

@external
@payable
def __default__():
    """
    @notice Receive ETH from Curve pool swaps
    """
    assert msg.sender == self.curve_pool.address

@external
@payable
def redeem(_account: address, _receiver: address, _lt_amount: uint256, _dt_amount: uint256, _data: Bytes[256]) -> uint256:
    """
    @notice Redeem discount token into locking token and lock into liquid locker
    @param _account User performing the redemption
    @param _receiver Receiver of rewards
    @param _lt_amount Amount of locking tokens
    @param _dt_amount Amount of discount tokens
    @param _data Additional data
    @return Amount of liquid locker tokens created
    @dev Can only be called by either of the reward contracts
    """
    assert msg.sender in [gauge_rewards, staking_rewards]
    assert _lt_amount > 0 or _dt_amount > 0

    # claim locking token rewards
    if _lt_amount > 0:
        assert locking_token.transferFrom(msg.sender, self, _lt_amount, default_return_value=True)
    amount: uint256 = _lt_amount + _dt_amount

    # redeem discount token rewards
    if _dt_amount > 0:
        assert discount_token.transferFrom(msg.sender, self, _dt_amount, default_return_value=True)
        if msg.value > 0:
            # redemption cost is paid for
            self._redeem_yearn(_receiver, _dt_amount, msg.value)
        else:
            # pay for redemption cost by selling some rewards
            sell_amount: uint256 = _abi_decode(_data, uint256)
            amount -= sell_amount
            self._redeem_curve(_receiver, _dt_amount, sell_amount)
    else:
        assert msg.value == 0

    # deposit into our lock and mint
    voting_escrow.modify_lock(amount, 0, proxy)
    minted: uint256 = liquid_locker.mint(_receiver)
    assert minted >= amount * SCALE
    log Redeem(_account, _receiver, _lt_amount, _dt_amount, msg.value, minted)
    return minted

@internal
def _redeem_yearn(_receiver: address, _amount: uint256, _eth_amount: uint256):
    """
    @notice Redeem through Yearn. Refunds any excess above 0.3%
    """
    value: uint256 = self.yearn_redemption.eth_required(_amount)
    assert value > 0
    if _eth_amount > value:
        # return anything above 0.3%
        raw_call(_receiver, b"", value=_eth_amount - value)
    value -= value * 3 / 1000
    assert _eth_amount >= value, "slippage"
    self.yearn_redemption.redeem(_amount, value=value)

@internal
def _redeem_curve(_receiver: address, _dt_amount: uint256, _sell_amount: uint256):
    """
    @notice Partial sell through Curve, then redeem through Yearn
    """
    # min_dy is set to zero because discount token redemption already has built in slippage check
    eth_amount: uint256 = self.curve_pool.exchange(0, 1, _sell_amount, 0, True)
    self._redeem_yearn(_receiver, _dt_amount - _sell_amount, eth_amount)

@external
def claim_excess():
    """
    @notice Claim excess ETH by sending it to the treasury
    """
    value: uint256 = self.balance
    assert value > 0
    raw_call(self.treasury, b"", value=value)
    log ClaimExcess(value)

@external
def set_treasury(_treasury: address):
    """
    @notice Set new treasury address, recipient of excess ETH
    @param _treasury Treasury address
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    self.treasury = _treasury
    log SetTreasury(_treasury)

@external
def set_yearn_redemption(_yearn_redemption: address):
    """
    @notice
        Set new Yearn redemption contract. Can be set to zero
        to effectively disable redemptions.
    @param _yearn_redemption Yearn redemption contract
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    previous: address = self.yearn_redemption.address
    if previous != empty(address):
        # retract previous allowance
        assert discount_token.approve(previous, 0, default_return_value=True)
    if _yearn_redemption != empty(address):
        # set new allowance
        assert discount_token.approve(_yearn_redemption, max_value(uint256), default_return_value=True)

    self.yearn_redemption = YearnRedemption(_yearn_redemption)
    log SetYearnRedemption(_yearn_redemption)

@external
def set_curve_pool(_curve_pool: address):
    """
    @notice
        Set new Curve pool contract. Can be set to zero
        to effectively disable redemptions without ETH.
    @param _curve_pool Curve pool contract
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    previous: address = self.curve_pool.address
    if previous != empty(address):
        # retract previous allowance
        assert discount_token.approve(previous, 0, default_return_value=True)
    if _curve_pool != empty(address):
        # set new allowance
        assert discount_token.approve(_curve_pool, max_value(uint256), default_return_value=True)

    self.curve_pool = CurvePool(_curve_pool)
    log SetCurvePool(_curve_pool)

@external
def set_management(_management: address):
    """
    @notice 
        Set the pending management address.
        Needs to be accepted by that account separately to transfer management over
    @param _management New pending management address
    """
    assert msg.sender == self.management
    self.pending_management = _management
    log PendingManagement(_management)

@external
def accept_management():
    """
    @notice 
        Accept management role.
        Can only be called by account previously marked as pending management by current management
    """
    assert msg.sender == self.pending_management
    self.pending_management = empty(address)
    self.management = msg.sender
    log SetManagement(msg.sender)
