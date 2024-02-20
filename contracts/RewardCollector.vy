# @version 0.3.10

from vyper.interfaces import ERC20

interface Gauge:
    def harvest() -> uint256: nonpayable

interface Registry:
    def gauge_map(_ygauge: address) -> address: view

interface Redeemer:
    def redeem(_account: address, _receiver: address, _amount: uint256, _data: Bytes[256]): payable

reward: public(immutable(ERC20))
registry: public(immutable(Registry))
redeemer: public(address)
packed_supply: public(HashMap[address, uint256])
packed_balances: public(HashMap[address, HashMap[address, uint256]])
pending_rewards: public(HashMap[address, uint256])
packed_fees: public(uint256)
owner: public(address)

PRECISION: constant(uint256) = 10**18
MASK: constant(uint256) = 2**128 - 1
FEE_DENOMINATOR: constant(uint256) = 10_000
FEE_MASK: constant(uint256) = 2**32 - 1

HARVEST_FEE_IDX: constant(uint256)     = 0 # harvest
FEE_IDX: constant(uint256)             = 1 # claim without redeem
REDEEM_SELL_FEE_IDX: constant(uint256) = 2 # claim with redeem, without ETH
REDEEM_FEE_IDX: constant(uint256)      = 3 # claim with redeem, with ETH

@external
def __init__(_redeemer: address, _reward: address, _registry: address):
    reward = ERC20(_reward)
    registry = Registry(_registry)
    self.redeemer = _redeemer
    self.owner = msg.sender

@external
@view
def claimable(_account: address, _gauges: DynArray[address, 32]) -> uint256:
    amount: uint256 = self.pending_rewards[_account]
    for gauge in _gauges:
        integral: uint256 = self._unpack(self.packed_supply[gauge])[1]
        balance: uint256 = 0
        account_integral: uint256 = 0
        balance, account_integral = self._unpack(self.packed_balances[gauge][_account])
        amount += (integral - account_integral) * balance / PRECISION
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

    fee: uint256 = FEE_IDX
    if len(_redeem_data) > 0:
        if msg.value > 0:
            fee = REDEEM_FEE_IDX
        else:
            fee = REDEEM_SELL_FEE_IDX
    fee = self._fee(fee)
    if fee > 0:
        fee = amount * fee / FEE_DENOMINATOR
        amount -= fee

    if len(_redeem_data) > 0:
        redeemer: address = self.redeemer
        assert reward.transfer(redeemer, amount, default_return_value=True)
        Redeemer(redeemer).redeem(msg.sender, _receiver, amount, _redeem_data, value=msg.value)
    else:
        assert reward.transfer(_receiver, amount, default_return_value=True)

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

        assert reward.transferFrom(gauge, self, amount, default_return_value=True)

    assert reward.transfer(_receiver, total_fees, default_return_value=True)
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
        assert reward.transferFrom(msg.sender, self, _rewards, default_return_value=True)

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
        account_balance, account_integral = self._unpack(self.packed_balances[msg.sender][_from])
        pending = (integral - account_integral) * account_balance / PRECISION
        if pending > 0:
            self.pending_rewards[_from] += pending
        self.packed_balances[msg.sender][_from] = self._pack(account_balance - _amount, integral)

    if _to == empty(address):
        # burn
        supply -= _amount
    else:
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
def fee(_idx: uint256) -> uint256:
    return self._fee(_idx)

@internal
@view
def _fee(_idx: uint256) -> uint256:
    assert _idx < 4
    return (self.packed_fees >> 32 * (4 + _idx)) & FEE_MASK

@external
def set_fee(_idx: uint256, _fee: uint256):
    assert msg.sender == self.owner
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
