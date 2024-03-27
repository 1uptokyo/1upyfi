# @version 0.3.10
"""
@title Gauge rewards
@author 1up
@license GNU AGPLv3
@notice
    Tracks supply, balances and rewards for all gauges.
    Gauges report changes in all these values to this contract.
    Rewards from gauges can be harvested by anyone in exchange for a share of the rewards.
    Users can claim their rewards as:
        - The naked reward token
        - Fully redeemed into the liquid locker token by paying for the redemption cost
        - Partially redeemed into the liquid locker token by selling some of the rewards to
            be able to pay for the redemption cost
    Each of these potentially has different fees associated to them.
"""

from vyper.interfaces import ERC20

interface Rewards:
    def report(_ygauge: address, _from: address, _to: address, _amount: uint256, _rewards: uint256): nonpayable
    def gauge_supply(_gauge: address) -> uint256: view
    def gauge_balance(_gauge: address, _account: address) -> uint256: view
implements: Rewards

interface Gauge:
    def harvest() -> uint256: nonpayable

interface Registry:
    def gauge_map(_ygauge: address) -> address: view

interface Redeemer:
    def redeem(_account: address, _receiver: address, _lt_amount: uint256, _dt_amount: uint256, _data: Bytes[256]) -> uint256: payable

discount_token: public(immutable(ERC20))
registry: public(immutable(Registry))
management: public(address)
pending_management: public(address)
redeemer: public(Redeemer)
treasury: public(address)
packed_supply: public(HashMap[address, uint256])
packed_balances: public(HashMap[address, HashMap[address, uint256]])
pending: public(HashMap[address, uint256])
packed_fees: public(uint256)

event Claim:
    account: indexed(address)
    receiver: address
    amount: uint256
    fee_idx: uint256
    fee: uint256

event Harvest:
    gauge: indexed(address)
    account: address
    amount: uint256
    fee: uint256

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
FEE_DENOMINATOR: constant(uint256) = 10_000
FEE_MASK: constant(uint256) = 2**32 - 1

HARVEST_FEE_IDX: constant(uint256)     = 0 # harvest
FEE_IDX: constant(uint256)             = 1 # claim without redeem
REDEEM_SELL_FEE_IDX: constant(uint256) = 2 # claim with redeem, without ETH
REDEEM_FEE_IDX: constant(uint256)      = 3 # claim with redeem, with ETH

@external
def __init__(_discount_token: address, _registry: address):
    """
    @notice Constructor
    @param _discount_token Token that can be redeemed at a discount, reward from gauges
    @param _registry Registry
    """
    discount_token = ERC20(_discount_token)
    registry = Registry(_registry)
    self.management = msg.sender
    self.treasury = msg.sender

@external
@view
def claimable(_gauge: address, _account: address) -> uint256:
    """
    @notice Get claimable rewards from a single gauge for a specific user
    @param _gauge Gauge to get claimable rewards for
    @param _account Account to get claimable rewards for
    @return Amount of laimable rewards
    """
    integral: uint256 = self._unpack(self.packed_supply[_gauge])[1]
    account_balance: uint256 = 0
    account_integral: uint256 = 0
    account_balance, account_integral = self._unpack(self.packed_balances[_gauge][_account])
    return (integral - account_integral) * account_balance / PRECISION

@external
@payable
@nonreentrant("lock")
def claim(_gauges: DynArray[address, 32], _receiver: address = msg.sender, _redeem_data: Bytes[256] = b"") -> uint256:
    """
    @notice Claim and optionally redeem rewards
    @param _gauges Gauges to claim rewards from
    @param _receiver Recipient of the rewards
    @param _redeem_data Data to pass along to the redeemer
    @return Amount of claimed rewards
    """
    amount: uint256 = self.pending[msg.sender]
    self.pending[msg.sender] = 0

    for gauge in _gauges:
        integral: uint256 = self._unpack(self.packed_supply[gauge])[1]
        balance: uint256 = 0
        account_integral: uint256 = 0
        balance, account_integral = self._unpack(self.packed_balances[gauge][msg.sender])
        if integral > account_integral:
            amount += (integral - account_integral) * balance / PRECISION
            self.packed_balances[gauge][msg.sender] = self._pack(balance, integral)

    redeem: bool = len(_redeem_data) > 0 or msg.value > 0
    fee_idx: uint256 = FEE_IDX
    if redeem:
        if msg.value > 0:
            # redeem by supplying ETH
            fee_idx = REDEEM_FEE_IDX
        else:
            # redeem by partially selling the rewards
            fee_idx = REDEEM_SELL_FEE_IDX
    fee: uint256 = self._fee_rate(fee_idx)
    if fee > 0:
        fee = amount * fee / FEE_DENOMINATOR
        amount -= fee
        self._set_pending_fees((self.packed_fees & MASK) + fee)

    log Claim(msg.sender, _receiver, amount, fee_idx, fee)

    if redeem:
        redeemer: Redeemer = self.redeemer
        assert redeemer.address != empty(address)
        return redeemer.redeem(msg.sender, _receiver, 0, amount, _redeem_data, value=msg.value)
    else:
        assert discount_token.transfer(_receiver, amount, default_return_value=True)
        return amount

@external
def harvest(_gauges: DynArray[address, 32], _amounts: DynArray[uint256, 32], _receiver: address = msg.sender) -> uint256:
    """
    @notice Harvest gauges for their rewards
    @param _gauges Gauges to harvest rewards from
    @param _amounts Reward amounts to harvest
    @param _receiver Recipient of harvest bounty
    @return Amount of rewards sent as harvest bounty
    """
    assert len(_gauges) == len(_amounts)
    fee_rate: uint256 = self._fee_rate(HARVEST_FEE_IDX)
    total_fees: uint256 = 0
    for i in range(32):
        if i == len(_gauges):
            break
        gauge: address = _gauges[i]
        amount: uint256 = _amounts[i]
        fees: uint256 = amount * fee_rate / FEE_DENOMINATOR
        amount -= fees

        supply: uint256 = 0
        integral: uint256 = 0
        supply, integral = self._harvest(gauge, amount, fees)

        if amount == 0 or supply == 0:
            continue
        
        total_fees += fees
        self.packed_supply[gauge] = self._pack(supply, integral)

    if total_fees > 0:
        assert discount_token.transfer(_receiver, total_fees, default_return_value=True)
    return total_fees

@external
def report(_ygauge: address, _from: address, _to: address, _amount: uint256, _rewards: uint256):
    """
    @notice Report a change in gauge state
    @param _ygauge Associated yearn gauge
    @param _from User that is sender of gauge tokens
    @param _to User that is receiver of gauge tokens
    @param _amount Amount of gauge tokens transferred
    @param _rewards Amount of new reward tokens
    @dev Sender and receiver may be zero to represent deposits and withdrawals respectively
    @dev Deposits are only allowed if the gauge is registered
    """
    supply: uint256 = 0
    integral: uint256 = 0
    supply, integral = self._harvest(msg.sender, _rewards, 0)

    if _from == empty(address) and _to == empty(address):
        assert _amount == 0 and _rewards > 0
        self.packed_supply[msg.sender] = self._pack(supply, integral)
        return
    assert _to not in [_from, self, msg.sender, _ygauge] and _amount > 0
    
    account_balance: uint256 = 0
    account_integral: uint256 = 0
    pending: uint256 = 0

    if _from == empty(address):
        # mint
        assert registry.gauge_map(_ygauge) == msg.sender # make sure gauge is registered
        supply += _amount
    else:
        # transfer - update account rewards
        account_balance, account_integral = self._unpack(self.packed_balances[msg.sender][_from])
        pending = (integral - account_integral) * account_balance / PRECISION
        if pending > 0:
            self.pending[_from] += pending
        self.packed_balances[msg.sender][_from] = self._pack(account_balance - _amount, integral)

    if _to == empty(address):
        # burn
        supply -= _amount
    else:
        # transfer - update account rewards
        account_balance, account_integral = self._unpack(self.packed_balances[msg.sender][_to])
        pending = (integral - account_integral) * account_balance / PRECISION
        if pending > 0:
            self.pending[_to] += pending
        self.packed_balances[msg.sender][_to] = self._pack(account_balance + _amount, integral)

    if supply > 0:
        # guard against precision attacks
        assert supply > PRECISION / 10**6

    self.packed_supply[msg.sender] = self._pack(supply, integral)

@external
@view
def gauge_supply(_gauge: address) -> uint256:
    """
    @notice Get the total supply of a gauge
    @param _gauge Gauge address
    @return Total supply
    """
    return self._unpack(self.packed_supply[_gauge])[0]

@external
@view
def gauge_balance(_gauge: address, _account: address) -> uint256:
    """
    @notice Get the user balance of a gauge
    @param _gauge Gauge address
    @param _account User
    @return User balance
    """
    return self._unpack(self.packed_balances[_gauge][_account])[0]

@external
@view
def pending_fees() -> uint256:
    """
    @notice Get the amount of pending fees
    @return Amount of pending fees
    """
    return self.packed_fees & MASK

@external
@view
def fee_rate(_idx: uint256) -> uint256:
    """
    @notice Get the fee rate of a specific type
    @param _idx Fee type
    @return Fee rate (bps)
    """
    assert _idx < 4
    return self._fee_rate(_idx)

@external
def claim_fees():
    """
    @notice Claim fees by sending them to the treasury
    """
    pending: uint256 = self.packed_fees & MASK
    self._set_pending_fees(0)
    assert pending > 0
    assert discount_token.transfer(self.treasury, pending, default_return_value=True)

@external
def set_redeemer(_redeemer: address):
    """
    @notice Set a new redeemer contract
    @param _redeemer Redeemer address
    @dev Retracts allowance for previous redeemer, if applicable
    @dev Sets allowance for new redeemer, if applicable
    @dev Can only be called by management
    """
    assert msg.sender == self.management

    previous: address = self.redeemer.address
    if previous != empty(address):
        # retract previous allowance
        assert discount_token.approve(previous, 0, default_return_value=True)
    if _redeemer != empty(address):
        # set new allowance
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
    assert _idx < 4
    assert _fee <= FEE_DENOMINATOR
    packed: uint256 = self.packed_fees
    sh: uint256 = 32 * (4 + _idx)
    packed &= ~(FEE_MASK << sh) # zero out old fee
    packed |= _fee << sh # write new fee
    self.packed_fees = packed
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

@internal
def _harvest(_gauge: address, _amount: uint256, _fees: uint256) -> (uint256, uint256):
    """
    @notice Harvest a gauge by transferring the reward tokens out of it and updating the integral
    """
    supply: uint256 = 0
    integral: uint256 = 0
    supply, integral = self._unpack(self.packed_supply[_gauge])

    if _amount == 0 or supply == 0:
        return supply, integral

    integral += _amount * PRECISION / supply
    assert discount_token.transferFrom(_gauge, self, _amount + _fees, default_return_value=True)
    log Harvest(_gauge, msg.sender, _amount, _fees)

    return supply, integral

@internal
@view
def _fee_rate(_idx: uint256) -> uint256:
    """
    @notice Unpack a specific fee type from packed slot
    """
    return (self.packed_fees >> 32 * (4 + _idx)) & FEE_MASK

@internal
def _set_pending_fees(_pending: uint256):
    """
    @notice Set pending fees in packed slot
    """
    assert _pending <= MASK
    packed: uint256 = self.packed_fees
    packed &= ~MASK # zero out old fee
    packed |= _pending # write new fee
    self.packed_fees = packed

@internal
@pure
def _pack(_amount: uint256, _integral: uint256) -> uint256:
    """
    @notice Pack amount and integral in a single slot
    """
    assert _amount <= MASK and _integral <= MASK
    return _amount | _integral << 128

@internal
@pure
def _unpack(_packed: uint256) -> (uint256, uint256):
    """
    @notice Unpack amount and integral from a single slot
    """
    return _packed & MASK, _packed >> 128
