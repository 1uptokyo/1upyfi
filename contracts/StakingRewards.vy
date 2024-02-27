# @version 0.3.10

from vyper.interfaces import ERC20

interface Rewards:
    def report(_account: address, _amount: uint256): nonpayable
implements: Rewards

interface Redeemer:
    def redeem(_account: address, _receiver: address, _lt_amount: uint256, _dt_amount: uint256, _data: Bytes[256]): payable

proxy: public(immutable(address))
staking: public(immutable(ERC20))
locking_token: public(immutable(ERC20))
discount_token: public(immutable(ERC20))
management: public(address)
pending_management: public(address)
treasury: public(address)
redeemer: public(Redeemer)
fee_rates: public(uint256[6])
packed_integrals: public(uint256)
packed_account_integrals: public(HashMap[address, uint256])
packed_pending_rewards: public(HashMap[address, uint256])
packed_pending_fees: public(uint256)

PRECISION: constant(uint256) = 10**18
MASK: constant(uint256) = 2**128 - 1
FEE_DENOMINATOR: constant(uint256) = 10_000

HARVEST_FEE_IDX: constant(uint256)        = 0 # harvest
DT_FEE_IDX: constant(uint256)             = 1 # claim discount token without redeem
DT_REDEEM_SELL_FEE_IDX: constant(uint256) = 2 # claim with redeem, without ETH
DT_REDEEM_FEE_IDX: constant(uint256)      = 3 # claim with redeem, with ETH
LT_FEE_IDX: constant(uint256)             = 4 # claim locking token without deposit into ll
LT_DEPOSIT_FEE_IDX: constant(uint256)     = 5 # claim locking token with deposit into ll

@external
def __init__(_proxy: address, _staking: address, _locking_token: address, _discount_token: address):
    proxy = _proxy
    staking = ERC20(_staking)
    locking_token = ERC20(_locking_token)
    discount_token = ERC20(_discount_token)
    self.management = msg.sender
    self.treasury = msg.sender

@external
def report(_account: address, _balance: uint256):
    assert msg.sender == staking.address
    self._sync(_account, _balance)

@external
@payable
def claim(_receiver: address = msg.sender, _redeem_data: Bytes[256] = b""):
    balance: uint256 = staking.balanceOf(msg.sender)
    self._sync(msg.sender, balance)

    lt_amount: uint256 = 0
    dt_amount: uint256 = 0
    lt_amount, dt_amount = self._unpack(self.packed_pending_rewards[msg.sender])

    lt_pending_fees: uint256 = 0
    dt_pending_fees: uint256 = 0
    lt_pending_fees, dt_pending_fees = self._unpack(self.packed_pending_fees)

    redeem: bool = len(_redeem_data) > 0 or msg.value > 0

    # locking token
    fee: uint256 = LT_FEE_IDX
    if redeem:
        # deposit into liquid locker
        fee = LT_DEPOSIT_FEE_IDX
    fee = lt_amount * self.fee_rates[fee] / FEE_DENOMINATOR
    lt_amount -= fee
    lt_pending_fees += fee

    # discount token
    fee = DT_FEE_IDX
    if redeem:
        if msg.value > 0:
            # redeem by supplying ETH
            fee = DT_REDEEM_FEE_IDX
        else:
            # redeem by partially selling the rewards
            fee = DT_REDEEM_SELL_FEE_IDX
    fee = dt_amount * self.fee_rates[fee] / FEE_DENOMINATOR
    dt_amount -= fee
    dt_pending_fees += fee

    self.packed_pending_rewards[msg.sender] = 0
    self.packed_pending_fees = self._pack(lt_pending_fees, dt_pending_fees)
    if redeem:
        redeemer: Redeemer = self.redeemer
        assert redeemer.address != empty(address)
        redeemer.redeem(msg.sender, _receiver, lt_amount, dt_amount, _redeem_data, value=msg.value)
    else:
        assert locking_token.transfer(_receiver, lt_amount, default_return_value=True)
        assert discount_token.transfer(_receiver, dt_amount, default_return_value=True)

@internal
def _sync(_account: address, _balance: uint256):
    lt_integral: uint256 = 0
    dt_integral: uint256 = 0
    lt_integral, dt_integral = self._unpack(self.packed_integrals)
    if _balance == 0:
        return

    lt_account_integral: uint256 = 0
    dt_account_integral: uint256 = 0
    lt_account_integral, dt_account_integral = self._unpack(self.packed_account_integrals[_account])

    if lt_account_integral == lt_integral and dt_account_integral == dt_integral:
        return

    lt_pending: uint256 = 0
    dt_pending: uint256 = 0
    lt_pending, dt_pending = self._unpack(self.packed_pending_rewards[_account])

    lt_pending += (lt_integral - lt_account_integral) * _balance / PRECISION
    dt_pending += (dt_integral - dt_account_integral) * _balance / PRECISION

    self.packed_account_integrals[_account] = self.packed_integrals
    self.packed_pending_rewards[_account] = self._pack(lt_pending, dt_pending)

@external
def harvest(_lt_amount: uint256, _dt_amount: uint256):
    assert _lt_amount > 0 or _dt_amount > 0

    if _lt_amount > 0:
        assert locking_token.transferFrom(proxy, self, _lt_amount, default_return_value=True)

    if _dt_amount > 0:
        assert discount_token.transferFrom(proxy, self, _dt_amount, default_return_value=True)

    lt_integral: uint256 = 0
    dt_integral: uint256 = 0
    lt_integral, dt_integral = self._unpack(self.packed_integrals)

    supply: uint256 = staking.totalSupply()
    assert supply > 0

    lt_integral += _lt_amount * PRECISION / supply
    dt_integral += _dt_amount * PRECISION / supply
    self.packed_integrals = self._pack(lt_integral, dt_integral)

@external
def claim_fees(_receiver: address = msg.sender):
    assert msg.sender == self.treasury
    lt_pending: uint256 = 0
    dt_pending: uint256 = 0
    lt_pending, dt_pending = self._unpack(self.packed_pending_fees)
    self.packed_pending_fees = 0

    if lt_pending > 0:
        assert locking_token.transfer(_receiver, lt_pending, default_return_value=True)

    if dt_pending > 0:
        assert discount_token.transfer(_receiver, dt_pending, default_return_value=True)

@external
def set_redeemer(_redeemer: address):
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

@external
def set_treasury(_treasury: address):
    assert msg.sender == self.management
    self.treasury = _treasury

@internal
@pure
def _pack(_a: uint256, _b: uint256) -> uint256:
    assert _a <= MASK and _b <= MASK
    return _a | _b << 128

@internal
@pure
def _unpack(_packed: uint256) -> (uint256, uint256):
    return _packed & MASK, _packed >> 128
