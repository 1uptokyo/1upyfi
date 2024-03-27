from ape import reverts
from pytest import fixture
from _constants import *

BIG_MASK = 2**112 - 1

@fixture
def proxy(accounts):
    return accounts[3]

@fixture
def locking_token(project, deployer):
    return project.MockToken.deploy(sender=deployer)

@fixture
def discount_token(project, deployer):
    return project.MockToken.deploy(sender=deployer)

@fixture
def staking_token(project, deployer):
    return project.MockToken.deploy(sender=deployer)

@fixture
def staking_and_rewards(project, deployer, proxy, locking_token, discount_token, staking_token):
    staking = project.Staking.deploy(staking_token, sender=deployer)
    rewards = project.StakingRewards.deploy(proxy, staking, locking_token, discount_token, sender=deployer)
    staking.set_rewards(rewards, sender=deployer)
    locking_token.approve(rewards, MAX_VALUE, sender=proxy)
    discount_token.approve(rewards, MAX_VALUE, sender=proxy)
    return staking, rewards

@fixture
def staking(staking_and_rewards):
    return staking_and_rewards[0]

@fixture
def rewards(staking_and_rewards):
    return staking_and_rewards[1]

def test_deposit(deployer, alice, bob, staking_token, staking):
    # depositing increases supply and user balance
    staking_token.mint(alice, UNIT, sender=deployer)
    staking_token.approve(staking, UNIT, sender=alice)
    assert staking_token.balanceOf(staking) == 0
    assert staking.totalSupply() == 0
    assert staking.balanceOf(bob) == 0
    staking.deposit(UNIT, bob, sender=alice)
    assert staking_token.balanceOf(staking) == UNIT
    assert staking.totalSupply() == UNIT
    assert staking.balanceOf(bob) == UNIT

def test_deposit_add(deployer, alice, staking_token, staking):
    # depositing adds to supply and user balance
    staking_token.mint(alice, 3 * UNIT, sender=deployer)
    staking_token.approve(staking, 3 * UNIT, sender=alice)
    staking.deposit(UNIT, sender=alice)
    staking.deposit(2 * UNIT, sender=alice)
    assert staking_token.balanceOf(staking) == 3 * UNIT
    assert staking.totalSupply() == 3 * UNIT
    assert staking.balanceOf(alice) == 3 * UNIT

def test_deposit_multiple(deployer, alice, bob, staking_token, staking):
    # deposits from multiple users updates supply and balance as expected
    staking_token.mint(alice, UNIT, sender=deployer)
    staking_token.approve(staking, UNIT, sender=alice)
    staking.deposit(UNIT, sender=alice)
    staking_token.mint(bob, 2 * UNIT, sender=deployer)
    staking_token.approve(staking, 2 * UNIT, sender=bob)
    staking.deposit(2 * UNIT, sender=bob)
    assert staking_token.balanceOf(staking) == 3 * UNIT
    assert staking.totalSupply() == 3 * UNIT
    assert staking.balanceOf(alice) == UNIT
    assert staking.balanceOf(bob) == 2 * UNIT

def test_deposit_excessive(deployer, alice, staking_token, staking):
    # cant deposit more than the balance
    staking_token.mint(alice, UNIT, sender=deployer)
    staking_token.approve(staking, UNIT, sender=alice)
    with reverts():
        staking.deposit(2 * UNIT, sender=alice)

def test_deposit_report(chain, deployer, alice, proxy, locking_token, discount_token, staking_token, staking, rewards):
    # depositing reports previous balance, updating user's integral
    staking_token.mint(alice, 3 * UNIT, sender=deployer)
    staking_token.approve(staking, 3 * UNIT, sender=alice)
    staking.deposit(2 * UNIT, sender=alice)

    locking_token.mint(proxy, 4 * UNIT, sender=deployer)
    discount_token.mint(proxy, 6 * UNIT, sender=deployer)
    rewards.harvest(4 * UNIT, 6 * UNIT, sender=deployer)
    chain.pending_timestamp += 2 * WEEK
    chain.mine()

    assert rewards.pending(alice) == (0, 0)
    assert rewards.claimable(alice) == (4 * UNIT, 6 * UNIT)
    staking.deposit(UNIT, sender=alice)
    assert rewards.pending(alice) == (4 * UNIT, 6 * UNIT)
    assert rewards.claimable(alice) == (4 * UNIT, 6 * UNIT)
    assert rewards.packed_account_integrals(alice) == rewards.packed_integrals()

def test_deposit_vote_weight(chain, deployer, alice, staking_token, staking):
    # depositing builds up voting weight over time
    staking_token.mint(alice, 32 * UNIT, sender=deployer)
    staking_token.approve(staking, 32 * UNIT, sender=alice)
    week = chain.pending_timestamp // WEEK + 1
    ts = week * WEEK + WEEK // 2
    chain.pending_timestamp = ts
    staking.deposit(32 * UNIT, sender=alice)
    assert staking.vote_weight(alice) == 0
    assert staking.previous_packed_balances(alice) == 0
    packed = staking.packed_balances(alice)
    assert packed >> 224 == week
    assert (packed >> 112) & BIG_MASK == ts
    assert packed & BIG_MASK == 32 * UNIT

    # snapshotted at beginning of week
    chain.pending_timestamp = ts + WEEK
    chain.mine()
    assert staking.vote_weight(alice) == 2 * UNIT # 32 * 0.5 / 8

    # constant throughout the week
    chain.pending_timestamp = ts + WEEK + DAY
    chain.mine()
    assert staking.vote_weight(alice) == 2 * UNIT # 32 * 0.5 / 8
    
    # snapshotted at beginning of next week
    chain.pending_timestamp = ts + 2 * WEEK
    chain.mine()
    assert staking.vote_weight(alice) == 6 * UNIT # 32 * 1.5 / 8

def test_deposit_later_vote_weight(chain, deployer, alice, staking_token, staking):
    # deposit in later week writes the 'previous' packed slot and recalculates staking time
    staking_token.mint(alice, 48 * UNIT, sender=deployer)
    staking_token.approve(staking, 48 * UNIT, sender=alice)
    week = chain.pending_timestamp // WEEK + 1
    ts = week * WEEK + WEEK // 2
    chain.pending_timestamp = ts
    staking.deposit(32 * UNIT, sender=alice)
    chain.pending_timestamp = ts + WEEK

    staking.deposit(16 * UNIT, sender=alice)
    packed = staking.previous_packed_balances(alice)
    assert packed >> 224 == week
    assert (packed >> 112) & BIG_MASK == ts
    assert packed & BIG_MASK == 32 * UNIT
    packed = staking.packed_balances(alice)
    assert packed >> 224 == week + 1
    assert (packed >> 112) & BIG_MASK == ts + WEEK // 3
    assert packed & BIG_MASK == 48 * UNIT

    # vote weight is based on the start of the week, when balance was lower
    assert staking.vote_weight(alice) == 2 * UNIT # 32 * 0.5 / 8
    chain.pending_timestamp = ts + WEEK + DAY
    chain.mine()
    assert staking.vote_weight(alice) == 2 * UNIT # 32 * 0.5 / 8

    # next weeks weight contains the second deposit
    chain.pending_timestamp = ts + 2 * WEEK
    chain.mine()
    assert staking.vote_weight(alice) == 7 * UNIT # (32 * 1.5 + 16 * 0.5) / 8

def test_deposit_locked_weight(chain, deployer, alice, staking_token, staking):
    # locking gives immediate vote weight
    staking_token.mint(alice, 32 * UNIT, sender=deployer)
    staking_token.approve(staking, 32 * UNIT, sender=alice)
    week = chain.pending_timestamp // WEEK + 1
    ts = week * WEEK + WEEK // 2
    chain.pending_timestamp = ts
    staking.deposit(32 * UNIT, sender=alice)
    chain.pending_timestamp = ts + WEEK
    staking.lock(2 * WEEK, sender=alice)
    chain.pending_timestamp = ts + 2 * WEEK
    chain.mine()
    assert staking.vote_weight(alice) == 14 * UNIT # 32 * 3.5 / 8

def test_deposit_max_locked_weight(chain, deployer, alice, staking_token, staking):
    # max locking caps weight
    staking_token.mint(alice, 32 * UNIT, sender=deployer)
    staking_token.approve(staking, 32 * UNIT, sender=alice)
    week = chain.pending_timestamp // WEEK + 1
    ts = week * WEEK + WEEK // 2
    chain.pending_timestamp = ts
    staking.deposit(32 * UNIT, sender=alice)
    chain.pending_timestamp = ts + WEEK
    staking.lock(sender=alice)
    chain.pending_timestamp = ts + 2 * WEEK
    chain.mine()
    assert staking.vote_weight(alice) == 32 * UNIT

def test_deposit_add_locked_weight(chain, deployer, alice, staking_token, staking):
    # depositing with a lock gives immediate vote weight
    staking_token.mint(alice, 96 * UNIT, sender=deployer)
    staking_token.approve(staking, 96 * UNIT, sender=alice)
    week = chain.pending_timestamp // WEEK + 1
    ts = week * WEEK + WEEK // 2
    chain.pending_timestamp = ts
    staking.deposit(32 * UNIT, sender=alice)
    chain.pending_timestamp = ts + WEEK
    staking.lock(4 * WEEK, sender=alice)
    chain.pending_timestamp = ts + 2 * WEEK
    staking.deposit(64 * UNIT, sender=alice)
    chain.pending_timestamp = ts + 3 * WEEK
    chain.mine()
    assert staking.vote_weight(alice) == 54 * UNIT # (32*6.5 + 64*3.5) / 8

def test_lock(chain, deployer, alice, staking_token, staking):
    # stake can be locked
    staking_token.mint(alice, UNIT, sender=deployer)
    staking_token.approve(staking, UNIT, sender=alice)
    staking.deposit(UNIT, sender=alice)
    assert staking.unlock_times(alice) == 0
    ts = chain.pending_timestamp
    staking.lock(2 * WEEK, sender=alice)
    assert staking.unlock_times(alice) == ts + 2 * WEEK

def test_lock_max(chain, deployer, alice, staking_token, staking):
    # lock duration is capped
    staking_token.mint(alice, UNIT, sender=deployer)
    staking_token.approve(staking, UNIT, sender=alice)
    ts = chain.pending_timestamp
    staking.deposit(UNIT, sender=alice)
    staking.lock(9 * WEEK, sender=alice)
    assert staking.unlock_times(alice) == ts + 8 * WEEK

def test_lock_excessive(chain, deployer, alice, staking_token, staking):
    # lock duration is no longer than necessary
    staking_token.mint(alice, UNIT, sender=deployer)
    staking_token.approve(staking, UNIT, sender=alice)
    ts = chain.pending_timestamp
    staking.deposit(UNIT, sender=alice)
    ts += WEEK
    chain.pending_timestamp = ts
    staking.lock(8 * WEEK, sender=alice)
    assert staking.unlock_times(alice) == ts + 7 * WEEK

def test_lock_reduce(deployer, alice, staking_token, staking):
    # cant reduce lock duration
    staking_token.mint(alice, UNIT, sender=deployer)
    staking_token.approve(staking, UNIT, sender=alice)
    staking.deposit(UNIT, sender=alice)
    staking.lock(sender=alice)
    with reverts():
        staking.lock(WEEK, sender=alice)

def test_relock(chain, deployer, alice, staking_token, staking):
    # cant relock when already at max
    staking_token.mint(alice, UNIT, sender=deployer)
    staking_token.approve(staking, UNIT, sender=alice)
    ts = chain.pending_timestamp
    staking.deposit(UNIT, sender=alice)
    chain.pending_timestamp = ts + 8 * WEEK
    with reverts():
        staking.lock(sender=alice)

def test_unstake(chain, deployer, alice, staking_token, staking):
    # unstaking starts a stream
    staking_token.mint(alice, 3 * UNIT, sender=deployer)
    staking_token.approve(staking, 3 * UNIT, sender=alice)
    staking.deposit(3 * UNIT, sender=alice)
    assert staking.streams(alice) == (0, 0, 0)
    ts = chain.pending_timestamp
    staking.unstake(2 * UNIT, sender=alice)
    assert staking.totalSupply() == UNIT
    assert staking.balanceOf(alice) == UNIT
    assert staking.streams(alice) == (ts, 2 * UNIT, 0)

def test_unstake_excessive(deployer, alice, staking_token, staking):
    # cant unstake more than balance
    staking_token.mint(alice, UNIT, sender=deployer)
    staking_token.approve(staking, UNIT, sender=alice)
    staking.deposit(UNIT, sender=alice)
    with reverts():
        staking.unstake(2 * UNIT, sender=alice)

def test_unstake_report(chain, deployer, alice, proxy, locking_token, discount_token, staking_token, staking, rewards):
    # balance is reported before unstaking
    staking_token.mint(alice, UNIT, sender=deployer)
    staking_token.approve(staking, UNIT, sender=alice)
    staking.deposit(UNIT, sender=alice)
    locking_token.mint(proxy, 2 * UNIT, sender=deployer)
    discount_token.mint(proxy, 3 * UNIT, sender=deployer)
    rewards.harvest(2 * UNIT, 3 * UNIT, sender=deployer)
    chain.pending_timestamp += 2 * WEEK
    staking.unstake(UNIT, sender=alice)
    assert rewards.packed_account_integrals(alice) == rewards.packed_integrals()
    assert rewards.pending(alice) == (2 * UNIT, 3 * UNIT)

def test_unstake_withdraw(chain, deployer, alice, bob, staking_token, staking):
    # once a stream is active, tokens can be withdrawn over time
    staking_token.mint(alice, 4 * UNIT, sender=deployer)
    staking_token.approve(staking, 4 * UNIT, sender=alice)
    staking.deposit(4 * UNIT, sender=alice)
    ts = chain.pending_timestamp
    staking.unstake(4 * UNIT, sender=alice)
    assert staking.maxWithdraw(alice) == 0
    chain.pending_timestamp = ts + WEEK // 4
    with chain.isolate():
        chain.mine()
        assert staking.maxWithdraw(alice) == UNIT
    with chain.isolate():
        staking.withdraw(UNIT, bob, sender=alice)
        assert staking.streams(alice) == (ts, 4 * UNIT, UNIT)
        assert staking.maxWithdraw(alice) == 0
        assert staking_token.balanceOf(bob) == UNIT
    chain.pending_timestamp = ts + WEEK // 2
    with chain.isolate():
        chain.mine()
        assert staking.maxWithdraw(alice) == 2 * UNIT
    with chain.isolate():
        staking.withdraw(2 * UNIT, bob, sender=alice)
        assert staking.streams(alice) == (ts, 4 * UNIT, 2 * UNIT)
        assert staking.maxWithdraw(alice) == 0
        assert staking_token.balanceOf(bob) == 2 * UNIT

def test_unstake_withdraw_multiple(chain, deployer, alice, staking_token, staking):
    # can withdraw multiple times from the stream
    staking_token.mint(alice, 4 * UNIT, sender=deployer)
    staking_token.approve(staking, 4 * UNIT, sender=alice)
    staking.deposit(4 * UNIT, sender=alice)
    ts = chain.pending_timestamp
    staking.unstake(4 * UNIT, sender=alice)
    chain.pending_timestamp = ts + WEEK // 4
    staking.withdraw(UNIT, sender=alice)
    chain.pending_timestamp = ts + WEEK * 3 // 4
    with chain.isolate():
        chain.mine()
        assert staking.maxWithdraw(alice) == 2 * UNIT
    staking.withdraw(UNIT, sender=alice)
    assert staking.streams(alice) == (ts, 4 * UNIT, 2 * UNIT)
    assert staking.maxWithdraw(alice) == UNIT
    assert staking_token.balanceOf(alice) == 2 * UNIT

def test_unstake_withdraw_excessive(chain, deployer, alice, staking_token, staking):
    # cant withdraw more than has been streamed
    staking_token.mint(alice, 4 * UNIT, sender=deployer)
    staking_token.approve(staking, 4 * UNIT, sender=alice)
    staking.deposit(4 * UNIT, sender=alice)
    ts = chain.pending_timestamp
    staking.unstake(4 * UNIT, sender=alice)
    chain.pending_timestamp = ts + WEEK // 4
    with reverts():
        staking.withdraw(2 * UNIT, sender=alice)

def test_unstake_withdraw_all(chain, deployer, alice, staking_token, staking):
    # after stream has ended the full amount can be withdrawn
    staking_token.mint(alice, 4 * UNIT, sender=deployer)
    staking_token.approve(staking, 4 * UNIT, sender=alice)
    staking.deposit(4 * UNIT, sender=alice)
    ts = chain.pending_timestamp
    staking.unstake(4 * UNIT, sender=alice)
    chain.pending_timestamp = ts + 2 * WEEK
    chain.mine()
    assert staking.maxWithdraw(alice) == 4 * UNIT
    staking.withdraw(4 * UNIT, sender=alice)
    assert staking.maxWithdraw(alice) == 0

def test_unstake_withdraw_from(chain, deployer, alice, bob, staking_token, staking):
    # third party with allowance can withdraw from a stream
    staking_token.mint(alice, 4 * UNIT, sender=deployer)
    staking_token.approve(staking, 4 * UNIT, sender=alice)
    staking.deposit(4 * UNIT, sender=alice)
    staking.unstake(4 * UNIT, sender=alice)
    chain.pending_timestamp += WEEK
    staking.approve(bob, 3 * UNIT, sender=alice)
    assert staking.allowance(alice, bob) == 3 * UNIT
    staking.withdraw(UNIT, deployer, alice, sender=bob)
    assert staking.maxWithdraw(alice) == 3 * UNIT
    assert staking.allowance(alice, bob) == 2 * UNIT
    assert staking_token.balanceOf(deployer) == UNIT

def test_unstake_withdraw_from_excessive(chain, deployer, alice, bob, staking_token, staking):
    # third party cant withdraw more than has been streamed
    staking_token.mint(alice, 4 * UNIT, sender=deployer)
    staking_token.approve(staking, 4 * UNIT, sender=alice)
    staking.deposit(4 * UNIT, sender=alice)
    ts = chain.pending_timestamp
    staking.unstake(4 * UNIT, sender=alice)
    chain.pending_timestamp = ts + WEEK // 2
    staking.approve(bob, 3 * UNIT, sender=alice)
    with reverts():
        staking.withdraw(3 * UNIT, deployer, alice, sender=bob)

def test_unstake_withdraw_from_allowance(chain, deployer, alice, bob, staking_token, staking):
    # third party cant withdraw more than their allowance
    staking_token.mint(alice, 4 * UNIT, sender=deployer)
    staking_token.approve(staking, 4 * UNIT, sender=alice)
    staking.deposit(4 * UNIT, sender=alice)
    staking.unstake(4 * UNIT, sender=alice)
    chain.pending_timestamp += WEEK
    staking.approve(bob, UNIT, sender=alice)
    with reverts():
        staking.withdraw(2 * UNIT, deployer, alice, sender=bob)

def test_unstake_merge(chain, deployer, alice, staking_token, staking):
    # unstaking with an existing stream adds unclaimed into the new one
    staking_token.mint(alice, 4 * UNIT, sender=deployer)
    staking_token.approve(staking, 4 * UNIT, sender=alice)
    staking.deposit(4 * UNIT, sender=alice)
    ts = chain.pending_timestamp
    staking.unstake(3 * UNIT, sender=alice)
    chain.pending_timestamp = ts + WEEK * 3 // 4
    staking.withdraw(2 * UNIT, sender=alice)
    ts = chain.pending_timestamp
    staking.unstake(UNIT, sender=alice)
    assert staking.streams(alice) == (ts, 2 * UNIT, 0)
    assert staking.maxWithdraw(alice) == 0

def test_unstake_locked(deployer, alice, staking_token, staking):
    # cant unstake with an active lock
    staking_token.mint(alice, UNIT, sender=deployer)
    staking_token.approve(staking, UNIT, sender=alice)
    staking.deposit(UNIT, sender=alice)
    staking.lock(WEEK, sender=alice)
    with reverts():
        staking.unstake(UNIT, sender=alice)

def test_unstake_lock_expired(chain, deployer, alice, staking_token, staking):
    # can unstake when lock has expired
    staking_token.mint(alice, UNIT, sender=deployer)
    staking_token.approve(staking, UNIT, sender=alice)
    staking.deposit(UNIT, sender=alice)
    staking.lock(WEEK, sender=alice)
    chain.pending_timestamp += WEEK
    staking.unstake(UNIT, sender=alice)

def test_transfer(deployer, alice, bob, staking_token, staking):
    # transferring updates balances but not supply
    staking_token.mint(alice, 3 * UNIT, sender=deployer)
    staking_token.approve(staking, 3 * UNIT, sender=alice)
    staking.deposit(3 * UNIT, sender=alice)
    staking.transfer(bob, UNIT, sender=alice)
    assert staking_token.balanceOf(staking) == 3 * UNIT
    assert staking.totalSupply() == 3 * UNIT
    assert staking.balanceOf(alice) == 2 * UNIT
    assert staking.balanceOf(bob) == UNIT

def test_transfer_locked(deployer, alice, bob, staking_token, staking):
    # cant transfer when stake is locked
    staking_token.mint(alice, 3 * UNIT, sender=deployer)
    staking_token.approve(staking, 3 * UNIT, sender=alice)
    staking.deposit(3 * UNIT, sender=alice)
    staking.lock(sender=alice)
    with reverts():
        staking.transfer(bob, UNIT, sender=alice)

def test_transfer_lock_expired(chain, deployer, alice, bob, staking_token, staking):
    # can transfer when stake lock has expired
    staking_token.mint(alice, 3 * UNIT, sender=deployer)
    staking_token.approve(staking, 3 * UNIT, sender=alice)
    staking.deposit(3 * UNIT, sender=alice)
    staking.lock(WEEK, sender=alice)
    chain.pending_timestamp += 2 * WEEK
    staking.transfer(bob, UNIT, sender=alice)

def test_transfer_excessive(deployer, alice, bob, staking_token, staking):
    # cant transfer more than balance
    staking_token.mint(alice, UNIT, sender=deployer)
    staking_token.approve(staking, UNIT, sender=alice)
    staking.deposit(UNIT, sender=alice)
    with reverts():
        staking.transfer(bob, 2 * UNIT, sender=alice)

def test_transfer_report(chain, deployer, alice, bob, proxy, locking_token, discount_token, staking_token, staking, rewards):
    # balances are reported before a transfer
    staking_token.mint(alice, UNIT, sender=deployer)
    staking_token.approve(staking, UNIT, sender=alice)
    staking.deposit(UNIT, sender=alice)
    locking_token.mint(proxy, 2 * UNIT, sender=deployer)
    discount_token.mint(proxy, 3 * UNIT, sender=deployer)
    rewards.harvest(2 * UNIT, 3 * UNIT, sender=deployer)
    chain.pending_timestamp += 2 * WEEK
    staking.transfer(bob, UNIT, sender=alice)
    packed = rewards.packed_integrals()
    assert rewards.packed_account_integrals(alice) == packed
    assert rewards.packed_account_integrals(bob) == packed
    assert rewards.pending(alice) == (2 * UNIT, 3 * UNIT)
    assert rewards.pending(bob) == (0, 0)

def test_transfer_from(deployer, alice, bob, staking_token, staking):
    # can transfer from other users if there's an allowance
    staking_token.mint(alice, 4 * UNIT, sender=deployer)
    staking_token.approve(staking, 4 * UNIT, sender=alice)
    staking.deposit(4 * UNIT, sender=alice)
    staking.approve(deployer, 3 * UNIT, sender=alice)
    staking.transferFrom(alice, bob, UNIT, sender=deployer)
    assert staking_token.balanceOf(staking) == 4 * UNIT
    assert staking.allowance(alice, deployer) == 2 * UNIT
    assert staking.totalSupply() == 4 * UNIT
    assert staking.balanceOf(alice) == 3 * UNIT
    assert staking.balanceOf(bob) == UNIT

def test_transfer_from_excessive(deployer, alice, bob, staking_token, staking):
    # cant transfer more from other user than the balance
    staking_token.mint(alice, UNIT, sender=deployer)
    staking_token.approve(staking, UNIT, sender=alice)
    staking.deposit(UNIT, sender=alice)
    staking.approve(bob, 2 * UNIT, sender=alice)
    with reverts():
        staking.transferFrom(alice, bob, 2 * UNIT, sender=bob)

def test_transfer_from_allowance_excessive(deployer, alice, bob, staking_token, staking):
    # cant transfer more from other user than the allowance
    staking_token.mint(alice, 2 * UNIT, sender=deployer)
    staking_token.approve(staking, 2 * UNIT, sender=alice)
    staking.deposit(2 * UNIT, sender=alice)
    staking.approve(bob, UNIT, sender=alice)
    with reverts():
        staking.transferFrom(alice, bob, 2 * UNIT, sender=bob)

def test_transfer_from_report(chain, deployer, alice, bob, proxy, locking_token, discount_token, staking_token, staking, rewards):
    # balances are reported before a transferFrom
    staking_token.mint(alice, UNIT, sender=deployer)
    staking_token.approve(staking, UNIT, sender=alice)
    staking.deposit(UNIT, sender=alice)
    locking_token.mint(proxy, 2 * UNIT, sender=deployer)
    discount_token.mint(proxy, 3 * UNIT, sender=deployer)
    rewards.harvest(2 * UNIT, 3 * UNIT, sender=deployer)
    staking.approve(deployer, UNIT, sender=alice)
    chain.pending_timestamp += 2 * WEEK
    staking.transferFrom(alice, bob, UNIT, sender=deployer)
    packed = rewards.packed_integrals()
    assert rewards.packed_account_integrals(alice) == packed
    assert rewards.packed_account_integrals(bob) == packed
    assert rewards.pending(alice) == (2 * UNIT, 3 * UNIT)
    assert rewards.pending(bob) == (0, 0)

def test_approve(alice, bob, staking):
    # set allowance
    assert staking.allowance(alice, bob) == 0
    staking.approve(bob, UNIT, sender=alice)
    assert staking.allowance(alice, bob) == UNIT

def test_set_rewards(deployer, proxy, locking_token, discount_token, staking, rewards):
    # rewards contract can be changed
    rewards2 = project.StakingRewards.deploy(proxy, staking, locking_token, discount_token, sender=deployer)
    assert staking.rewards() == rewards
    staking.set_rewards(rewards2, sender=deployer)
    assert staking.rewards() == rewards2

def test_set_rewards_permission(deployer, alice, proxy, locking_token, discount_token, staking):
    # only management can change rewards contract
    rewards2 = project.StakingRewards.deploy(proxy, staking, locking_token, discount_token, sender=deployer)
    with reverts():
        staking.set_rewards(rewards2, sender=alice)

def test_set_management(deployer, alice, staking):
    # management can propose a replacement
    assert staking.management() == deployer
    assert staking.pending_management() == ZERO_ADDRESS
    staking.set_management(alice, sender=deployer)
    assert staking.management() == deployer
    assert staking.pending_management() == alice

def test_set_management_undo(deployer, alice, staking):
    # proposed replacement can be undone
    staking.set_management(alice, sender=deployer)
    staking.set_management(ZERO_ADDRESS, sender=deployer)
    assert staking.management() == deployer
    assert staking.pending_management() == ZERO_ADDRESS

def test_set_management_permission(alice, staking):
    # only management can propose a replacement
    with reverts():
        staking.set_management(alice, sender=alice)

def test_accept_management(deployer, alice, staking):
    # replacement can accept management role
    staking.set_management(alice, sender=deployer)
    staking.accept_management(sender=alice)
    assert staking.management() == alice
    assert staking.pending_management() == ZERO_ADDRESS

def test_accept_management_early(alice, staking):
    # cant accept management role without being nominated
    with reverts():
        staking.accept_management(sender=alice)

def test_accept_management_wrong(deployer, alice, bob, staking):
    # cant accept management role without being the nominee
    staking.set_management(alice, sender=deployer)
    with reverts():
        staking.accept_management(sender=bob)
