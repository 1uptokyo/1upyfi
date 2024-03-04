# @version 0.3.10

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
    assert msg.sender == self.curve_pool.address

@external
@payable
def redeem(_account: address, _receiver: address, _lt_amount: uint256, _dt_amount: uint256, _data: Bytes[256]) -> uint256:
    assert msg.sender in [gauge_rewards, staking_rewards]
    assert _lt_amount > 0 or _dt_amount > 0

    if _lt_amount > 0:
        assert locking_token.transferFrom(msg.sender, self, _lt_amount, default_return_value=True)
    amount: uint256 = _lt_amount + _dt_amount

    if _dt_amount > 0:
        assert discount_token.transferFrom(msg.sender, self, _dt_amount, default_return_value=True)
        if msg.value > 0:
            self._redeem_yearn(_receiver, _dt_amount, msg.value)
        else:
            sell_amount: uint256 = _abi_decode(_data, uint256)
            amount -= sell_amount
            self._redeem_curve(_receiver, _dt_amount, sell_amount)
    else:
        assert msg.value == 0

    # deposit into our lock and mint
    voting_escrow.modify_lock(amount, 0, proxy)
    minted: uint256 = liquid_locker.mint(_receiver)
    assert minted >= amount * SCALE
    return minted

@internal
def _redeem_yearn(_receiver: address, _amount: uint256, _eth_amount: uint256):
    value: uint256 = self.yearn_redemption.eth_required(_amount)
    value -= value * 3 / 1000
    assert value > 0
    assert _eth_amount >= value, "slippage"
    self.yearn_redemption.redeem(_amount, value=value)

@internal
def _redeem_curve(_receiver: address, _dt_amount: uint256, _sell_amount: uint256):
    # min_dy is set to zero because discount token redemption already has built in slippage check
    eth_amount: uint256 = self.curve_pool.exchange(0, 1, _sell_amount, 0, True)
    self._redeem_yearn(_receiver, _dt_amount - _sell_amount, eth_amount)

@external
def claim_excess():
    value: uint256 = self.balance
    assert value > 0
    raw_call(self.treasury, b"", value=value)

@external
def set_treasury(_treasury: address):
    assert msg.sender == self.management
    self.treasury = _treasury

@external
def set_yearn_redemption(_yearn_redemption: address):
    assert msg.sender == self.management

    previous: address = self.yearn_redemption.address
    if previous != empty(address):
        # retract previous allowance
        assert discount_token.approve(previous, 0, default_return_value=True)
    if _yearn_redemption != empty(address):
        # set new allowance
        assert discount_token.approve(_yearn_redemption, max_value(uint256), default_return_value=True)

    self.yearn_redemption = YearnRedemption(_yearn_redemption)

@external
def set_curve_pool(_curve_pool: address):
    assert msg.sender == self.management

    previous: address = self.curve_pool.address
    if previous != empty(address):
        # retract previous allowance
        assert discount_token.approve(previous, 0, default_return_value=True)
    if _curve_pool != empty(address):
        # set new allowance
        assert discount_token.approve(_curve_pool, max_value(uint256), default_return_value=True)

    self.curve_pool = CurvePool(_curve_pool)

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
