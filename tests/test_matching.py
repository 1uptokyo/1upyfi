from ape import reverts
from pytest import fixture
from _constants import *

SCALE = 69_420 * UNIT

@fixture
def staking_and_rewards(project, deployer, proxy, locking_token, discount_token, liquid_locker):
    staking = project.Staking.deploy(liquid_locker, sender=deployer)
    rewards = project.StakingRewards.deploy(proxy, staking, locking_token, discount_token, sender=deployer)
    staking.set_rewards(rewards, sender=deployer)
    return staking, rewards

@fixture
def staking(staking_and_rewards):
    return staking_and_rewards[0]

@fixture
def rewards(staking_and_rewards):
    return staking_and_rewards[1]

@fixture
def matching(project, ychad, deployer, alice, staking):
    return project.Matching.deploy(staking, ychad, alice, 2_500, sender=deployer)

def test_match(ychad, alice, locking_token, liquid_locker, staking, matching):
    # locked yfi is matched at the specified rate
    locking_token.transfer(matching, 3 * UNIT, sender=ychad)
    locking_token.approve(liquid_locker, 8 * UNIT, sender=ychad)
    liquid_locker.deposit(8 * UNIT, sender=ychad)
    assert locking_token.balanceOf(matching) == 3 * UNIT
    assert staking.balanceOf(alice) == 0
    assert matching.matched() == 0
    assert matching.match(sender=alice).return_value == (2 * UNIT, 2 * SCALE)
    assert locking_token.balanceOf(matching) == UNIT
    assert staking.balanceOf(alice) == 2 * SCALE
    assert matching.matched() == 2 * UNIT

def test_match_sequential(ychad, alice, locking_token, liquid_locker, matching):
    # cant match more than once in a row without additional deposits
    locking_token.transfer(matching, 3 * UNIT, sender=ychad)
    locking_token.approve(liquid_locker, 8 * UNIT, sender=ychad)
    liquid_locker.deposit(8 * UNIT, sender=ychad)
    matching.match(sender=alice)
    with reverts():
        matching.match(sender=alice)

def test_match_multiple(ychad, alice, locking_token, liquid_locker, staking, matching):
    # matching multiple times only matches the difference
    locking_token.transfer(matching, 10 * UNIT, sender=ychad)
    locking_token.approve(liquid_locker, 12 * UNIT, sender=ychad)
    liquid_locker.deposit(8 * UNIT, sender=ychad)
    assert matching.match(sender=alice).return_value == (2 * UNIT, 2 * SCALE)
    assert staking.balanceOf(alice) == 2 * SCALE
    assert matching.matched() == 2 * UNIT
    liquid_locker.deposit(4 * UNIT, sender=ychad)
    assert matching.match(sender=alice).return_value == (UNIT, SCALE)
    assert locking_token.balanceOf(matching) == 7 * UNIT
    assert staking.balanceOf(alice) == 3 * SCALE
    assert matching.matched() == 3 * UNIT

def test_match_available(ychad, alice, locking_token, liquid_locker, staking, matching):
    # can only match however many tokens are in the matching contract
    locking_token.transfer(matching, 3 * UNIT, sender=ychad)
    locking_token.approve(liquid_locker, 20 * UNIT, sender=ychad)
    liquid_locker.deposit(8 * UNIT, sender=ychad)
    assert matching.match(sender=alice).return_value == (2 * UNIT, 2 * SCALE)
    assert staking.balanceOf(alice) == 2 * SCALE
    assert matching.matched() == 2 * UNIT
    liquid_locker.deposit(12 * UNIT, sender=ychad)
    assert matching.match(sender=alice).return_value == (UNIT, SCALE)
    assert locking_token.balanceOf(matching) == 0
    assert staking.balanceOf(alice) == 3 * SCALE
    assert matching.matched() == 3 * UNIT

def test_match_permission(ychad, bob, locking_token, liquid_locker, matching):
    # only recipient can claim matched tokens
    locking_token.transfer(matching, 3 * UNIT, sender=ychad)
    locking_token.approve(liquid_locker, 8 * UNIT, sender=ychad)
    liquid_locker.deposit(8 * UNIT, sender=ychad)
    with reverts():
        matching.match(sender=bob)

def test_revoke(ychad, locking_token, matching):
    # tokens can be revoked
    locking_token.transfer(matching, 3 * UNIT, sender=ychad)
    assert locking_token.balanceOf(matching) == 3 * UNIT
    pre = locking_token.balanceOf(ychad)
    matching.revoke(locking_token, UNIT, sender=ychad)
    assert locking_token.balanceOf(matching) == 2 * UNIT
    assert locking_token.balanceOf(ychad) == pre + UNIT

def test_revoke_permission(ychad, alice, locking_token, matching):
    # only owner can revoke tokens
    locking_token.transfer(matching, 3 * UNIT, sender=ychad)
    with reverts():
        matching.revoke(locking_token, UNIT, sender=alice)
