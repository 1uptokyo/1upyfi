# @version 0.3.10

from vyper.interfaces import ERC20
from vyper.interfaces import ERC4626
implements: ERC20
implements: ERC4626

interface Rewards:
    def report(_account: address, _balance: uint256): nonpayable

asset: public(immutable(address))
management: public(address)
pending_management: public(address)
rewards: public(Rewards)
totalSupply: public(uint256)
previous_packed_balances: public(HashMap[address, uint256]) # week | time | balance
packed_balances: public(HashMap[address, uint256]) # week | time | balance
packed_streams: public(HashMap[address, uint256]) # time | total | claimed
unlock_times: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])

decimals: public(constant(uint8)) = 18
name: public(constant(String[21])) = "Staked 1UP Locked YFI"
symbol: public(constant(String[6])) = "supYFI"

event Transfer:
    _from: indexed(address)
    _to: indexed(address)
    _value: uint256

event Approval:
    _owner: indexed(address)
    _spender: indexed(address)
    _value: uint256

event Deposit:
    _sender: indexed(address)
    _owner: indexed(address)
    _assets: uint256
    _shares: uint256

event Withdraw:
    _sender: indexed(address)
    _receiver: indexed(address)
    _owner: indexed(address)
    _assets: uint256
    _shares: uint256

SMALL_MASK: constant(uint256) = 2**32 - 1
BIG_MASK: constant(uint256) = 2**112 - 1
DAY_LENGTH: constant(uint256) = 24 * 60 * 60
WEEK_LENGTH: constant(uint256) = 7 * DAY_LENGTH
RAMP_LENGTH: constant(uint256) = 8 * WEEK_LENGTH
INCREMENT: constant(bool) = True
DECREMENT: constant(bool) = False

@external
def __init__(_asset: address):
    asset = _asset

@external
@view
def balanceOf(_account: address) -> uint256:
    return self.packed_balances[_account] & BIG_MASK

@external
def transfer(_to: address, _value: uint256) -> bool:
    assert _to != empty(address) and _to != self
    assert _value > 0

    self._update_balance(_value, msg.sender, DECREMENT)
    self._update_balance(_value, _to, INCREMENT)
    log Transfer(msg.sender, _to, _value)
    return True

@external
def transferFrom(_from: address, _to: address, _value: uint256) -> bool:
    assert _to != empty(address) and _to != self
    assert _value > 0

    allowance: uint256 = self.allowance[_from][msg.sender] - _value
    self.allowance[_from][msg.sender] = allowance
    log Approval(_from, msg.sender, allowance)

    self._update_balance(_value, _from, DECREMENT)
    self._update_balance(_value, _to, INCREMENT)
    log Transfer(_from, _to, _value)
    return True

@external
def approve(_spender: address, _value: uint256) -> bool:
    assert _spender != empty(address)

    self.allowance[msg.sender][_spender] = _value
    log Approval(msg.sender, _spender, _value)
    return True

@view
@external
def totalAssets() -> uint256:
    return self.totalSupply

@view
@external
def convertToShares(_assets: uint256) -> uint256:
    return _assets

@view
@external
def convertToAssets(_shares: uint256) -> uint256:
    return _shares

@view
@external
def maxDeposit(_owner: address) -> uint256:
    return max_value(uint256)

@view
@external
def previewDeposit(_assets: uint256) -> uint256:
    return _assets

@external
def deposit(_assets: uint256, _receiver: address = msg.sender) -> uint256:
    self._deposit(_assets, _receiver)
    return _assets

@view
@external
def maxMint(_owner: address) -> uint256:
    return max_value(uint256)

@view
@external
def previewMint(_shares: uint256) -> uint256:
    return _shares

@external
def mint(_shares: uint256, _receiver: address = msg.sender) -> uint256:
    self._deposit(_shares, _receiver)
    return _shares

@view
@external
def maxWithdraw(_owner: address) -> uint256:
    return self._withdrawable(_owner)

@view
@external
def previewWithdraw(_assets: uint256) -> uint256:
    return _assets

@external
def withdraw(_assets: uint256, _receiver: address = msg.sender, _owner: address = msg.sender) -> uint256:
    self._withdraw(_assets, _receiver, _owner)
    return _assets

@view
@external
def maxRedeem(_owner: address) -> uint256:
    return self._withdrawable(_owner)

@view
@external
def previewRedeem(_shares: uint256) -> uint256:
    return _shares

@external
def redeem(_shares: uint256, _receiver: address = msg.sender, _owner: address = msg.sender) -> uint256:
    self._withdraw(_shares, _receiver, _owner)
    return _shares

@external
def lock(_duration: uint256) -> uint256:
    old_duration: uint256 = self.unlock_times[msg.sender]
    if old_duration > block.timestamp:
        old_duration -= block.timestamp
    else:
        old_duration = 0

    current_week: uint256 = block.timestamp / WEEK_LENGTH
    week: uint256 = 0
    time: uint256 = 0
    balance: uint256 = 0
    week, time, balance = self._unpack(self.packed_balances[msg.sender])

    if current_week > week:
        self.previous_packed_balances[msg.sender] = self.packed_balances[msg.sender]

    new_duration: uint256 = min(_duration, RAMP_LENGTH)
    assert new_duration > old_duration or balance == 0
    
    if balance > 0:
        if time == 0:
            time = block.timestamp
        time -= new_duration - old_duration
    else:
        time = 0

    self.packed_balances[msg.sender] = self._pack(current_week, time, balance)

    unlock_time: uint256 = block.timestamp + new_duration
    self.unlock_times[msg.sender] = unlock_time
    return unlock_time

@external
def unstake(_assets: uint256):
    assert _assets > 0
    self.totalSupply -= _assets
    self._update_balance(_assets, msg.sender, DECREMENT)

    time: uint256 = 0
    total: uint256 = 0
    claimed: uint256 = 0
    time, total, claimed = self._unpack(self.packed_streams[msg.sender])
    self.packed_streams[msg.sender] = self._pack(block.timestamp, total - claimed + _assets, 0)
    log Transfer(msg.sender, empty(address), _assets)

@internal
def _deposit(_assets: uint256, _receiver: address):
    self.totalSupply += _assets
    self._update_balance(_assets, _receiver, INCREMENT)

    assert ERC20(asset).transferFrom(msg.sender, self, _assets, default_return_value=True)
    log Deposit(msg.sender, _receiver, _assets, _assets)
    log Transfer(empty(address), _receiver, _assets)

@external
@view
def vote_weight(_account: address) -> uint256:
    last_week: uint256 = block.timestamp / WEEK_LENGTH - 1

    week: uint256 = 0
    time: uint256 = 0
    balance: uint256 = 0
    week, time, balance = self._unpack(self.packed_balances[_account])

    if week > last_week:
        week, time, balance = self._unpack(self.previous_packed_balances[_account])

    if balance == 0:
        return 0

    time = (block.timestamp / WEEK_LENGTH * WEEK_LENGTH) - time
    return balance * min(time, RAMP_LENGTH) / RAMP_LENGTH

@external
def set_rewards(_rewards: address):
    assert msg.sender == self.management
    self.rewards = Rewards(_rewards)

@internal
@view
def _withdrawable(_account: address) -> uint256:
    time: uint256 = 0
    total: uint256 = 0
    claimed: uint256 = 0
    time, total, claimed = self._unpack(self.packed_streams[_account])
    if time == 0:
        return 0
    time = min(block.timestamp - time, WEEK_LENGTH)
    return total * time / WEEK_LENGTH - claimed

@internal
def _withdraw(_assets: uint256, _receiver: address, _owner: address):
    if _owner != msg.sender:
        allowance: uint256 = self.allowance[_owner][msg.sender] - _assets
        self.allowance[_owner][msg.sender] = allowance
        log Approval(_owner, msg.sender, allowance)

    time: uint256 = 0
    total: uint256 = 0
    claimed: uint256 = 0
    time, total, claimed = self._unpack(self.packed_streams[_owner])
    assert time > 0

    claimed += _assets
    claimable: uint256 = min(block.timestamp - time, WEEK_LENGTH)
    claimable = total * claimable / WEEK_LENGTH
    assert claimed <= claimable

    if claimed < total:
        self.packed_streams[_owner] = self._pack(time, total, claimed)
    else:
        self.packed_streams[_owner] = 0

    assert ERC20(asset).transfer(_receiver, _assets, default_return_value=True)
    log Withdraw(_owner, _receiver, _owner, _assets, _assets)

@internal
def _update_balance(_amount: uint256, _account: address, _increment: bool):
    lock_duration: uint256 = self.unlock_times[_account]
    if lock_duration > block.timestamp:
        lock_duration -= block.timestamp
    else:
        lock_duration = 0

    current_week: uint256 = block.timestamp / WEEK_LENGTH
    week: uint256 = 0
    time: uint256 = 0
    balance: uint256 = 0
    week, time, balance = self._unpack(self.packed_balances[_account])

    # sync rewards
    self.rewards.report(_account, balance)

    if _increment == INCREMENT:
        if time > 0:
            time = min(block.timestamp - time, RAMP_LENGTH)
        time = block.timestamp - (balance * time + _amount * lock_duration) / (balance + _amount)
        balance += _amount
    else:
        assert lock_duration == 0
        balance -= _amount
        if balance == 0:
            time = 0

    if current_week > week:
        self.previous_packed_balances[_account] = self.packed_balances[_account]

    self.packed_balances[_account] = self._pack(current_week, time, balance)

@internal
@pure
def _pack(_a: uint256, _b: uint256, _c: uint256) -> uint256:
    assert _a <= SMALL_MASK and _b <= BIG_MASK and _c <= BIG_MASK
    return (_a << 224) | (_b << 112) | _c

@internal
@pure
def _unpack(_packed: uint256) -> (uint256, uint256, uint256):
    return _packed >> 224, (_packed >> 112) & BIG_MASK, _packed & BIG_MASK
