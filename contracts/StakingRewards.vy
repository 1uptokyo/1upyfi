# @version 0.3.10
"""
@title Staking rewards
@author 1up
@license GNU AGPLv3
@notice
    Tracks rewards for stakers.
    Staking contract report changes in balances to this contract.
    Assumes that any amount of locking token and discount token in the proxy is a reward for stakers.
    Rewards can be harvested by anyone in exchange for a share of the rewards.
    Users can claim their rewards as:
        - The naked reward token
        - Fully redeemed into the liquid locker token by paying for the redemption cost
        - Partially redeemed into the liquid locker token by selling some of the rewards to
            be able to pay for the redemption cost
    Each of these potentially has different fees associated to them.
"""

from vyper.interfaces import ERC20

interface Rewards:
    def report(_account: address, _amount: uint256, _supply: uint256): nonpayable
implements: Rewards

interface Redeemer:
    def redeem(_account: address, _receiver: address, _lt_amount: uint256, _dt_amount: uint256, _data: Bytes[256]) -> uint256: payable

proxy: public(immutable(address))
staking: public(immutable(ERC20))
locking_token: public(immutable(ERC20))
discount_token: public(immutable(ERC20))
management: public(address)
pending_management: public(address)
redeemer: public(Redeemer)
treasury: public(address)
fee_rates: public(uint256[6])
packed_integrals: public(uint256)
packed_streaming: public(uint256) # updated | lt_amount | dt_amount
packed_next: public(uint256)
packed_account_integrals: public(HashMap[address, uint256])
packed_pending_rewards: public(HashMap[address, uint256])
packed_pending_fees: public(uint256)

event Claim:
    account: indexed(address)
    receiver: address
    lt_amount: uint256
    dt_amount: uint256
    fee_idx: uint256
    lt_fee: uint256
    dt_fee: uint256

event ClaimFees:
    lt_amount: uint256
    dt_amount: uint256

event Harvest:
    account: address
    lt_amount: uint256
    dt_amount: uint256
    lt_fee: uint256
    dt_fee: uint256

event SetRedeemer:
    redeemer: address

event SetTreasury:
    treasury: address

event SetFeeRate:
    idx: uint256
    rate: uint256

event PendingManagement:
    management: address

event SetManagement:
    management: address

PRECISION: constant(uint256) = 10**18
MASK: constant(uint256) = 2**128 - 1
SMALL_MASK: constant(uint256) = 2**32 - 1
BIG_MASK: constant(uint256) = 2**112 - 1
WEEK_LENGTH: constant(uint256) = 7 * 24 * 60 * 60
FEE_DENOMINATOR: constant(uint256) = 10_000

HARVEST_FEE_IDX: constant(uint256)        = 0 # harvest
DT_FEE_IDX: constant(uint256)             = 1 # claim discount token without redeem
DT_REDEEM_SELL_FEE_IDX: constant(uint256) = 2 # claim with redeem, without ETH
DT_REDEEM_FEE_IDX: constant(uint256)      = 3 # claim with redeem, with ETH
LT_FEE_IDX: constant(uint256)             = 4 # claim locking token without deposit into ll
LT_DEPOSIT_FEE_IDX: constant(uint256)     = 5 # claim locking token with deposit into ll

@external
def __init__(_proxy: address, _staking: address, _locking_token: address, _discount_token: address):
    """
    @notice Constructor
    @param _proxy Proxy
    @param _staking Staking contract
    @param _locking_token Token that can be locked into the voting escrow
    @param _discount_token Token that can be redeemed at a discount
    """
    proxy = _proxy
    staking = ERC20(_staking)
    locking_token = ERC20(_locking_token)
    discount_token = ERC20(_discount_token)
    self.management = msg.sender
    self.treasury = msg.sender
    self.packed_streaming = self._pack_triplet(block.timestamp, 0, 0)

@external
@view
def pending(_account: address) -> (uint256, uint256):
    """
    @notice Get the pending rewards of a user
    @param _account User to get pending rewards for
    @return Tuple with pending locking token and discount token rewards
    """
    return self._unpack(self.packed_pending_rewards[_account])

@external
@view
def claimable(_account: address) -> (uint256, uint256):
    """
    @notice Get the amount of claimable rewards of a user
    @param _account User to get claimable rewards for
    @return Tuple with claimable locking token and discount token rewards
    """
    balance: uint256 = staking.balanceOf(_account)
    supply: uint256 = staking.totalSupply()

    current_week: uint256 = block.timestamp / WEEK_LENGTH
    lt_integral: uint256 = 0
    dt_integral: uint256 = 0
    lt_integral, dt_integral = self._unpack(self.packed_integrals)

    updated: uint256 = 0
    lt_streaming: uint256 = 0
    dt_streaming: uint256 = 0
    updated, lt_streaming, dt_streaming = self._unpack_triplet(self.packed_streaming)

    if supply > 0 and updated < block.timestamp:
        # update integrals
        streaming_week: uint256 = updated / WEEK_LENGTH
        if current_week > streaming_week:
            # new week: unlock all streaming rewards
            updated = current_week * WEEK_LENGTH
            lt_integral += lt_streaming * PRECISION / supply
            dt_integral += dt_streaming * PRECISION / supply

            lt_next: uint256 = 0
            dt_next: uint256 = 0
            lt_next, dt_next = self._unpack(self.packed_next)

            if current_week > streaming_week + 1:
                # unlock all next rewards
                lt_streaming = 0
                dt_streaming = 0
                lt_integral += lt_next * PRECISION / supply
                dt_integral += dt_next * PRECISION / supply
            else:
                # next rewards start streaming
                lt_streaming = lt_next
                dt_streaming = dt_next

        # update streams
        remaining: uint256 = (current_week + 1) * WEEK_LENGTH - updated
        passed: uint256 = block.timestamp - updated # guaranteed to be <= remaining
        lt_integral += (lt_streaming * passed / remaining) * PRECISION / supply
        dt_integral += (dt_streaming * passed / remaining) * PRECISION / supply

    lt_account_integral: uint256 = 0
    dt_account_integral: uint256 = 0
    lt_account_integral, dt_account_integral = self._unpack(self.packed_account_integrals[_account])

    lt_pending: uint256 = 0
    dt_pending: uint256 = 0
    lt_pending, dt_pending = self._unpack(self.packed_pending_rewards[_account])

    lt_pending += (lt_integral - lt_account_integral) * balance / PRECISION
    dt_pending += (dt_integral - dt_account_integral) * balance / PRECISION

    return lt_pending, dt_pending

@external
@payable
@nonreentrant("lock")
def claim(_receiver: address = msg.sender, _redeem_data: Bytes[256] = b"") -> (uint256, uint256):
    """
    @notice Claim staking rewards
    @param _receiver Rewards receiver
    @param _redeem_data Additional data
    @return
        With redemption: tuple of liquid locker token rewards and zero
        Without redemption: tuple of locking token and discount token rewards
    """
    balance: uint256 = staking.balanceOf(msg.sender)
    supply: uint256 = staking.totalSupply()

    lt_amount: uint256 = 0
    dt_amount: uint256 = 0
    lt_amount, dt_amount = self._sync_user(msg.sender, balance, supply)

    lt_pending_fees: uint256 = 0
    dt_pending_fees: uint256 = 0
    lt_pending_fees, dt_pending_fees = self._unpack(self.packed_pending_fees)

    redeem: bool = len(_redeem_data) > 0 or msg.value > 0

    # locking token
    lt_fee: uint256 = LT_FEE_IDX
    if redeem:
        # deposit into liquid locker
        lt_fee = LT_DEPOSIT_FEE_IDX
    lt_fee = lt_amount * self.fee_rates[lt_fee] / FEE_DENOMINATOR
    lt_amount -= lt_fee
    lt_pending_fees += lt_fee

    # discount token
    fee_idx: uint256 = DT_FEE_IDX
    if redeem:
        if msg.value > 0:
            # redeem by supplying ETH
            fee_idx = DT_REDEEM_FEE_IDX
        else:
            # redeem by partially selling the rewards
            fee_idx = DT_REDEEM_SELL_FEE_IDX
    dt_fee: uint256 = dt_amount * self.fee_rates[fee_idx] / FEE_DENOMINATOR
    dt_amount -= dt_fee
    dt_pending_fees += dt_fee

    # update pending amounts
    self.packed_pending_rewards[msg.sender] = 0
    self.packed_pending_fees = self._pack(lt_pending_fees, dt_pending_fees)
    log Claim(msg.sender, _receiver, lt_amount, dt_amount, fee_idx, lt_fee, dt_fee)

    if redeem:
        redeemer: Redeemer = self.redeemer
        assert redeemer.address != empty(address)
        amount: uint256 = redeemer.redeem(msg.sender, _receiver, lt_amount, dt_amount, _redeem_data, value=msg.value)
        return amount, 0
    else:
        # no redemption, transfer naked tokens
        assert locking_token.transfer(_receiver, lt_amount, default_return_value=True)
        assert discount_token.transfer(_receiver, dt_amount, default_return_value=True)
        return lt_amount, dt_amount

@external
def harvest(_lt_amount: uint256, _dt_amount: uint256, _receiver: address = msg.sender):
    """
    @notice Harvest staking rewards in exchange for a bounty
    @param _lt_amount Amount of locking tokens to harvest
    @param _dt_amount Amount of discount tokens to harvest
    @param _receiver Recipient of harvest bounty
    """
    assert _lt_amount > 0 or _dt_amount > 0
    lt_amount: uint256 = _lt_amount
    dt_amount: uint256 = _dt_amount
    fee_rate: uint256 = self.fee_rates[HARVEST_FEE_IDX]

    # harvest locking tokens
    lt_fee: uint256 = 0
    if lt_amount > 0:
        assert locking_token.transferFrom(proxy, self, lt_amount, default_return_value=True)
        if fee_rate > 0:
            lt_fee = lt_amount * fee_rate / FEE_DENOMINATOR
            lt_amount -= lt_fee
            assert locking_token.transfer(_receiver, lt_fee, default_return_value=True)

    # harvest discount tokens
    dt_fee: uint256 = 0
    if _dt_amount > 0:
        assert discount_token.transferFrom(proxy, self, dt_amount, default_return_value=True)
        if fee_rate > 0:
            dt_fee = dt_amount * fee_rate / FEE_DENOMINATOR
            dt_amount -= dt_fee
            assert discount_token.transfer(_receiver, dt_fee, default_return_value=True)

    supply: uint256 = staking.totalSupply()
    assert supply > 0
    self._sync(supply)

    lt_next: uint256 = 0
    dt_next: uint256 = 0
    lt_next, dt_next = self._unpack(self.packed_next)
    self.packed_next = self._pack(lt_next + lt_amount, dt_next + dt_amount)
    log Harvest(msg.sender, lt_amount, dt_amount, lt_fee, dt_fee)

@external
def report(_account: address, _balance: uint256, _supply: uint256):
    """
    @notice Report balance to sync reward integrals prior to a change
    @param _account Account
    @param _balance Balance before the change
    @param _supply Supply before the change
    """
    assert msg.sender == staking.address
    self._sync_user(_account, _balance, _supply)

@external
@view
def pending_fees() -> (uint256, uint256):
    return self._unpack(self.packed_pending_fees)

@external
def claim_fees():
    """
    @notice Claim fees by sending them to the treasury
    """
    treasury: address = self.treasury

    lt_pending: uint256 = 0
    dt_pending: uint256 = 0
    lt_pending, dt_pending = self._unpack(self.packed_pending_fees)
    self.packed_pending_fees = 0

    if lt_pending > 0:
        assert locking_token.transfer(treasury, lt_pending, default_return_value=True)

    if dt_pending > 0:
        assert discount_token.transfer(treasury, dt_pending, default_return_value=True)
    log ClaimFees(lt_pending, dt_pending)

@external
def set_redeemer(_redeemer: address):
    """
    @notice Set a new redeemer contract
    @param _redeemer Redeemer address
    @dev Retracts allowances for previous redeemer, if applicable
    @dev Sets allowances for new redeemer, if applicable
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    previous: address = self.redeemer.address
    if previous != empty(address):
        # retract previous allowances
        assert locking_token.approve(previous, 0, default_return_value=True)
        assert discount_token.approve(previous, 0, default_return_value=True)
    if _redeemer != empty(address):
        # set new allowances
        assert locking_token.approve(_redeemer, max_value(uint256), default_return_value=True)
        assert discount_token.approve(_redeemer, max_value(uint256), default_return_value=True)

    self.redeemer = Redeemer(_redeemer)
    log SetRedeemer(_redeemer)

@external
def set_treasury(_treasury: address):
    """
    @notice Set a new treasury, recipient of fees
    @param _treasury Treasury address
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    self.treasury = _treasury
    log SetTreasury(_treasury)

@external
def set_fee_rate(_idx: uint256, _fee: uint256):
    """
    @notice Set the fee rate for a specific fee type
    @param _idx Fee type
    @param _fee Fee rate (bps)
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _idx < 6
    if _idx == HARVEST_FEE_IDX:
        assert _fee <= FEE_DENOMINATOR / 10
    else:
        assert _fee <= FEE_DENOMINATOR / 2
    self.fee_rates[_idx] = _fee
    log SetFeeRate(_idx, _fee)

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

@external
def sync():
    """
    @notice Sync global rewards. Updates rewards streams and integrals
    """
    self._sync(staking.totalSupply())

@internal
def _sync(_supply: uint256) -> (uint256, uint256):
    """
    @notice Sync global rewards. Needs to be called before harvest and user sync
    """
    current_week: uint256 = block.timestamp / WEEK_LENGTH
    lt_integral: uint256 = 0
    dt_integral: uint256 = 0
    lt_integral, dt_integral = self._unpack(self.packed_integrals)

    updated: uint256 = 0
    lt_streaming: uint256 = 0
    dt_streaming: uint256 = 0
    updated, lt_streaming, dt_streaming = self._unpack_triplet(self.packed_streaming)

    if _supply == 0 or updated == block.timestamp:
        # nothing staked or already up-to-date: do nothing
        return lt_integral, dt_integral

    streaming_week: uint256 = updated / WEEK_LENGTH
    if current_week > streaming_week:
        # new week: unlock all streaming rewards
        updated = current_week * WEEK_LENGTH # beginnning of this week
        lt_integral += lt_streaming * PRECISION / _supply
        dt_integral += dt_streaming * PRECISION / _supply

        lt_next: uint256 = 0
        dt_next: uint256 = 0
        lt_next, dt_next = self._unpack(self.packed_next)
        self.packed_next = 0

        if current_week > streaming_week + 1:
            # unlock all next rewards
            lt_streaming = 0
            dt_streaming = 0
            lt_integral += lt_next * PRECISION / _supply
            dt_integral += dt_next * PRECISION / _supply
        else:
            # next rewards start streaming
            lt_streaming = lt_next
            dt_streaming = dt_next

    # update streams
    remaining: uint256 = (current_week + 1) * WEEK_LENGTH - updated # always <= WEEK_LENGTH
    passed: uint256 = block.timestamp - updated # always <= remaining
    unlocked: uint256 = 0

    unlocked = lt_streaming * passed / remaining
    lt_integral += unlocked * PRECISION / _supply
    lt_streaming -= unlocked

    unlocked = dt_streaming * passed / remaining
    dt_integral += unlocked * PRECISION / _supply
    dt_streaming -= unlocked

    self.packed_streaming = self._pack_triplet(block.timestamp, lt_streaming, dt_streaming)
    self.packed_integrals = self._pack(lt_integral, dt_integral)
    return lt_integral, dt_integral

@internal
def _sync_user(_account: address, _balance: uint256, _supply: uint256) -> (uint256, uint256):
    """
    @notice Sync a user's rewards. Needs to be called before the balance is changed
    """
    lt_pending: uint256 = 0
    dt_pending: uint256 = 0
    lt_pending, dt_pending = self._unpack(self.packed_pending_rewards[_account])

    lt_integral: uint256 = 0
    dt_integral: uint256 = 0
    lt_integral, dt_integral = self._sync(_supply)
    if _balance == 0:
        # no rewards to be distributed, sync integrals only
        self.packed_account_integrals[_account] = self.packed_integrals
        return lt_pending, dt_pending

    lt_account_integral: uint256 = 0
    dt_account_integral: uint256 = 0
    lt_account_integral, dt_account_integral = self._unpack(self.packed_account_integrals[_account])

    if lt_account_integral == lt_integral and dt_account_integral == dt_integral:
        return lt_pending, dt_pending

    lt_pending += (lt_integral - lt_account_integral) * _balance / PRECISION
    dt_pending += (dt_integral - dt_account_integral) * _balance / PRECISION

    self.packed_account_integrals[_account] = self.packed_integrals
    self.packed_pending_rewards[_account] = self._pack(lt_pending, dt_pending)
    return lt_pending, dt_pending

@internal
@pure
def _pack(_a: uint256, _b: uint256) -> uint256:
    """
    @notice Pack two values into two equally sized parts of a single slot
    """
    assert _a <= MASK and _b <= MASK
    return _a | (_b << 128)

@internal
@pure
def _unpack(_packed: uint256) -> (uint256, uint256):
    """
    @notice Unpack two values from two equally sized parts of a single slot
    """
    return _packed & MASK, _packed >> 128

@internal
@pure
def _pack_triplet(_a: uint256, _b: uint256, _c: uint256) -> uint256:
    """
    @notice Pack a small value and two big values into a single storage slot
    """
    assert _a <= SMALL_MASK and _b <= BIG_MASK and _c <= BIG_MASK
    return (_a << 224) | (_b << 112) | _c

@internal
@pure
def _unpack_triplet(_packed: uint256) -> (uint256, uint256, uint256):
    """
    @notice Unpack a small value and two big values from a single storage slot
    """
    return _packed >> 224, (_packed >> 112) & BIG_MASK, _packed & BIG_MASK
