# @version 0.3.10
"""
@title Staking
@author 1up
@license GNU AGPLv3
@notice
    Vault with 1:1 of underlying liquid locker token.
    Vote weight increases linearly over a period of 4 epochs.
    Vote weights are snapshotted at the start of the week.
    Deposits can be locked to receive a larger vote weight up front.
    After unstaking the underlying tokens are streamed out over a week.
"""

from vyper.interfaces import ERC20
from vyper.interfaces import ERC4626
implements: ERC20
implements: ERC4626

interface Rewards:
    def report(_account: address, _amount: uint256, _supply: uint256): nonpayable

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

event SetRewards:
    rewards: address

event PendingManagement:
    management: address

event SetManagement:
    management: address

SMALL_MASK: constant(uint256) = 2**32 - 1
BIG_MASK: constant(uint256) = 2**112 - 1
DAY_LENGTH: constant(uint256) = 24 * 60 * 60
WEEK_LENGTH: constant(uint256) = 7 * DAY_LENGTH
RAMP_LENGTH: constant(uint256) = 8 * WEEK_LENGTH
INCREMENT: constant(bool) = True
DECREMENT: constant(bool) = False

@external
def __init__(_asset: address):
    """
    @notice Constructor
    @param _asset Underlying liquid locker
    """
    asset = _asset
    self.management = msg.sender

@external
@view
def balanceOf(_account: address) -> uint256:
    """
    @notice Get the staking balance of a user
    @param _account User
    @return Staking balance
    """
    return self.packed_balances[_account] & BIG_MASK

@external
def transfer(_to: address, _value: uint256) -> bool:
    """
    @notice Transfer tokens to another user
    @param _to User to transfer tokens to
    @param _value Amount of tokens to transfer
    @return Always True
    """
    assert _to != empty(address) and _to != self

    if _value > 0:
        self._update_balance(_value, msg.sender, DECREMENT)
        self._update_balance(_value, _to, INCREMENT)

    log Transfer(msg.sender, _to, _value)
    return True

@external
def transferFrom(_from: address, _to: address, _value: uint256) -> bool:
    """
    @notice Transfer another user's tokens by spending an allowance
    @param _from User to transfer tokens from
    @param _to User to transfer tokens to
    @param _value Amount of tokens to transfer
    @return Always True
    """
    assert _to != empty(address) and _to != self
    
    if _value > 0:
        allowance: uint256 = self.allowance[_from][msg.sender] - _value
        self.allowance[_from][msg.sender] = allowance

        self._update_balance(_value, _from, DECREMENT)
        self._update_balance(_value, _to, INCREMENT)

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
    return self.totalSupply

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
    return self._withdrawable(_owner)

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
    @dev Requires unstaking before assets become withdrawable over the next week
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
    return self._withdrawable(_owner)

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
    @dev Requires unstaking before assets become withdrawable over the next week
    """
    self._withdraw(_shares, _receiver, _owner)
    return _shares

@external
def lock(_duration: uint256 = max_value(uint256)) -> uint256:
    """
    @notice Lock all of caller's assets for a duration
    @param _duration Lock duration in seconds
    @return Unlock timestamp
    @dev Locks are capped at 4 epochs
    @dev Affects entire position, even assets staked after the lock was created
    """
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
    assert balance > 0

    # snapshot
    if current_week > week:
        self.previous_packed_balances[msg.sender] = self.packed_balances[msg.sender]

    # dont lock longer than needed
    additional: uint256 = _duration - old_duration
    max_needed: uint256 = RAMP_LENGTH - min(block.timestamp - time, RAMP_LENGTH)
    additional = min(additional, max_needed)
    assert additional > 0
    
    # calculate new timestamp
    time -= additional

    self.packed_balances[msg.sender] = self._pack(current_week, time, balance)

    unlock_time: uint256 = block.timestamp + old_duration + additional
    self.unlock_times[msg.sender] = unlock_time
    return unlock_time

@external
def unstake(_assets: uint256):
    """
    @notice Unstake assets, streaming them out over a week
    @param _assets Amount of assets to unstake
    @dev Adds existing stream to new stream, if applicable
    """
    assert _assets > 0
    self._update_balance(_assets, msg.sender, DECREMENT)
    self.totalSupply -= _assets

    time: uint256 = 0
    total: uint256 = 0
    claimed: uint256 = 0
    time, total, claimed = self._unpack(self.packed_streams[msg.sender])
    self.packed_streams[msg.sender] = self._pack(block.timestamp, total - claimed + _assets, 0)
    log Transfer(msg.sender, empty(address), _assets)

@external
@view
def streams(_account: address) -> (uint256, uint256, uint256):
    """
    @notice Get a user's stream details
    @param _account User address
    @return Tuple with stream start time, stream amount, claimed amount
    """
    return self._unpack(self.packed_streams[_account])

@external
@view
def vote_weight(_account: address) -> uint256:
    """
    @notice Get account vote weight
    @param _account Account
    @return Vote weight
    @dev Snapshotted at beginning of the week
    """
    last_week: uint256 = block.timestamp / WEEK_LENGTH - 1

    week: uint256 = 0
    time: uint256 = 0
    balance: uint256 = 0
    week, time, balance = self._unpack(self.packed_balances[_account])

    # snapshot
    if week > last_week:
        week, time, balance = self._unpack(self.previous_packed_balances[_account])

    if balance == 0:
        return 0

    time = block.timestamp / WEEK_LENGTH * WEEK_LENGTH - time
    return balance * min(time, RAMP_LENGTH) / RAMP_LENGTH

@external
def set_rewards(_rewards: address):
    """
    @notice Set staking rewards contract
    @param _rewards Rewards contract
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _rewards != empty(address)
    self.rewards = Rewards(_rewards)
    log SetRewards(_rewards)

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
def _deposit(_assets: uint256, _receiver: address):
    """
    @notice Update balance and transfer liquid locker tokens in
    """
    self._update_balance(_assets, _receiver, INCREMENT)
    self.totalSupply += _assets

    assert ERC20(asset).transferFrom(msg.sender, self, _assets, default_return_value=True)
    log Deposit(msg.sender, _receiver, _assets, _assets)
    log Transfer(empty(address), _receiver, _assets)

@internal
@view
def _withdrawable(_account: address) -> uint256:
    """
    @notice Get amount released from unstaking stream
    """
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
    """
    @notice Withdraw from the stream
    """
    if _owner != msg.sender:
        allowance: uint256 = self.allowance[_owner][msg.sender] - _assets
        self.allowance[_owner][msg.sender] = allowance

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
    """
    @notice Update balance and time. Supply should be updated _after_ calling this function
    """
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
    self.rewards.report(_account, balance, self.totalSupply)

    if _increment == INCREMENT:
        if time > 0:
            time = min(block.timestamp - time, RAMP_LENGTH)
        # amount-weighted average time
        time = block.timestamp - (balance * time + _amount * lock_duration) / (balance + _amount)
        balance += _amount
    else:
        assert lock_duration == 0
        balance -= _amount
        if balance == 0:
            time = 0

    # snapshot
    if current_week > week:
        self.previous_packed_balances[_account] = self.packed_balances[_account]

    self.packed_balances[_account] = self._pack(current_week, time, balance)

@internal
@pure
def _pack(_a: uint256, _b: uint256, _c: uint256) -> uint256:
    """
    @notice Pack a small value and two big values into a single storage slot
    """
    assert _a <= SMALL_MASK and _b <= BIG_MASK and _c <= BIG_MASK
    return (_a << 224) | (_b << 112) | _c

@internal
@pure
def _unpack(_packed: uint256) -> (uint256, uint256, uint256):
    """
    @notice Unpack a small value and two big values from a single storage slot
    """
    return _packed >> 224, (_packed >> 112) & BIG_MASK, _packed & BIG_MASK
