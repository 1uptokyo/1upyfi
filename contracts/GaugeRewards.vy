# @version 0.3.10

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
    def redeem(_account: address, _receiver: address, _amount: uint256, _data: Bytes[256]): payable

reward_token: public(immutable(ERC20))
registry: public(immutable(Registry))
management: public(address)
pending_management: public(address)
redeemer: public(Redeemer)
treasury: public(address)
packed_supply: public(HashMap[address, uint256])
packed_balances: public(HashMap[address, HashMap[address, uint256]])
pending_rewards: public(HashMap[address, uint256])
packed_fees: public(uint256)

PRECISION: constant(uint256) = 10**18
MASK: constant(uint256) = 2**128 - 1
FEE_DENOMINATOR: constant(uint256) = 10_000
FEE_MASK: constant(uint256) = 2**32 - 1

HARVEST_FEE_IDX: constant(uint256)     = 0 # harvest
FEE_IDX: constant(uint256)             = 1 # claim without redeem
REDEEM_SELL_FEE_IDX: constant(uint256) = 2 # claim with redeem, without ETH
REDEEM_FEE_IDX: constant(uint256)      = 3 # claim with redeem, with ETH

@external
def __init__(_reward_token: address, _registry: address):
    reward_token = ERC20(_reward_token)
    registry = Registry(_registry)
    self.management = msg.sender

@external
@view
def claimable(_account: address, _gauges: DynArray[address, 32]) -> uint256:
    amount: uint256 = self.pending_rewards[_account]
    for gauge in _gauges:
        integral: uint256 = self._unpack(self.packed_supply[gauge])[1]
        account_balance: uint256 = 0
        account_integral: uint256 = 0
        account_balance, account_integral = self._unpack(self.packed_balances[gauge][_account])
        amount += (integral - account_integral) * account_balance / PRECISION
    return amount

@external
@payable
def claim(_gauges: DynArray[address, 32], _receiver: address = msg.sender, _redeem_data: Bytes[256] = b""):
    amount: uint256 = self.pending_rewards[msg.sender]
    self.pending_rewards[msg.sender] = 0

    for gauge in _gauges:
        integral: uint256 = self._unpack(self.packed_supply[gauge])[1]
        balance: uint256 = 0
        account_integral: uint256 = 0
        balance, account_integral = self._unpack(self.packed_balances[gauge][msg.sender])
        if integral > account_integral:
            amount += (integral - account_integral) * balance / PRECISION
            self.packed_balances[gauge][msg.sender] = self._pack(balance, integral)

    redeem: bool = len(_redeem_data) > 0 or msg.value > 0
    fee: uint256 = FEE_IDX
    if redeem:
        if msg.value > 0:
            # redeem by supplying ETH
            fee = REDEEM_FEE_IDX
        else:
            # redeem by partially selling the rewards
            fee = REDEEM_SELL_FEE_IDX
    fee = self._fee_rate(fee)
    if fee > 0:
        fee = amount * fee / FEE_DENOMINATOR
        amount -= fee
        self._set_pending_fees((self.packed_fees & MASK) + fee)

    if redeem:
        redeemer: Redeemer = self.redeemer
        assert redeemer.address != empty(address)
        redeemer.redeem(msg.sender, _receiver, amount, _redeem_data, value=msg.value)
    else:
        assert reward_token.transfer(_receiver, amount, default_return_value=True)

@external
def harvest(_gauges: DynArray[address, 32], _receiver: address = msg.sender) -> uint256:
    fee_rate: uint256 = (self.packed_fees >> 128) & FEE_MASK
    total_fees: uint256 = 0
    for gauge in _gauges:
        supply: uint256 = 0
        integral: uint256 = 0
        supply, integral = self._unpack(self.packed_supply[gauge])
        if supply == 0:
            continue

        amount: uint256 = Gauge(gauge).harvest()
        fees: uint256 = amount * fee_rate / FEE_DENOMINATOR
        amount -= fees
        total_fees += fees

        integral += amount * PRECISION / supply
        self.packed_supply[gauge] = self._pack(supply, integral)

        assert reward_token.transferFrom(gauge, self, amount, default_return_value=True)

    assert reward_token.transfer(_receiver, total_fees, default_return_value=True)
    return total_fees

@external
@view
def gauge_supply(_gauge: address) -> uint256:
    return self._unpack(self.packed_supply[_gauge])[0]

@external
@view
def gauge_balance(_gauge: address, _account: address) -> uint256:
    return self._unpack(self.packed_balances[_gauge][_account])[0]

@external
def report(_ygauge: address, _from: address, _to: address, _amount: uint256, _rewards: uint256):
    assert _from != empty(address) or _to != empty(address) or _rewards > 0

    supply: uint256 = 0
    integral: uint256 = 0
    supply, integral = self._unpack(self.packed_supply[msg.sender])

    if _from == empty(address):
        # deposit into gauge, make sure it is registered
        assert registry.gauge_map(_ygauge) == msg.sender

    if _rewards > 0 and supply > 0:
        integral += _rewards * PRECISION / supply
        assert reward_token.transferFrom(msg.sender, self, _rewards, default_return_value=True)

    if _from == empty(address) and _to == empty(address):
        self.packed_supply[msg.sender] = self._pack(supply, integral)
        return
    assert _amount > 0
    
    account_balance: uint256 = 0
    account_integral: uint256 = 0
    pending: uint256 = 0

    if _from == empty(address):
        # mint
        supply += _amount
    else:
        # transfer - update account rewards
        account_balance, account_integral = self._unpack(self.packed_balances[msg.sender][_from])
        pending = (integral - account_integral) * account_balance / PRECISION
        if pending > 0:
            self.pending_rewards[_from] += pending
        self.packed_balances[msg.sender][_from] = self._pack(account_balance - _amount, integral)

    if _to == empty(address):
        # burn
        supply -= _amount
    else:
        # transfer - update account rewards
        account_balance, account_integral = self._unpack(self.packed_balances[msg.sender][_to])
        pending = (integral - account_integral) * account_balance / PRECISION
        if pending > 0:
            self.pending_rewards[_to] += pending
        self.packed_balances[msg.sender][_to] = self._pack(account_balance + _amount, integral)

    if supply > 0:
        assert supply > PRECISION / 1000
    self.packed_supply[msg.sender] = self._pack(supply, integral)

@external
@view
def pending_fees() -> uint256:
    return self.packed_fees & MASK

@external
@view
def fee_rate(_idx: uint256) -> uint256:
    return self._fee(_idx)

@internal
@view
def _fee_rate(_idx: uint256) -> uint256:
    assert _idx < 4
    return (self.packed_fees >> 32 * (4 + _idx)) & FEE_MASK

@internal
def _set_pending_fees(_pending: uint256):
    assert _pending <= MASK
    packed: uint256 = self.packed_fees
    packed &= ~MASK # zero out old fee
    packed |= _pending # write new fee
    self.packed_fees = packed

@external
def claim_fees(_receiver: address = msg.sender):
    assert msg.sender == self.treasury
    pending: uint256 = self.packed_fees & MASK
    assert reward_token.transfer(_receiver, pending, default_return_value=True)

@external
def set_redeemer(_redeemer: address):
    assert msg.sender == self.management

    previous: address = self.redeemer.address
    if previous != empty(address):
        # retract previous allowance
        assert reward_token.approve(previous, 0, default_return_value=True)
    if _redeemer != empty(address):
        # set new allowance
        assert reward_token.approve(_redeemer, max_value(uint256), default_return_value=True)

    self.redeemer = Redeemer(_redeemer)

@external
def set_treasury(_treasury: address):
    assert msg.sender == self.management
    self.treasury = _treasury

@external
def set_fee_rate(_idx: uint256, _fee: uint256):
    assert msg.sender == self.management
    assert _idx < 4
    assert _fee <= FEE_DENOMINATOR
    packed: uint256 = self.packed_fees
    sh: uint256 = 32 * (4 + _idx)
    packed &= ~(FEE_MASK << sh) # zero out old fee
    packed |= _fee << sh # write new fee
    self.packed_fees = packed

@internal
@pure
def _pack(_amount: uint256, _integral: uint256) -> uint256:
    assert _amount <= MASK and _integral <= MASK
    return _amount | _integral << 128

@internal
@pure
def _unpack(_packed: uint256) -> (uint256, uint256):
    return _packed & MASK, _packed >> 128
