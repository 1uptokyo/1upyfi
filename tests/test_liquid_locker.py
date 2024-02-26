import ape
from pytest import fixture
from _constants import *

SCALE = 69_420 * UNIT

@fixture
def liquid_locker(project, deployer, locking_token, voting_escrow, proxy):
    locker = project.LiquidLocker.deploy(locking_token, voting_escrow, proxy, sender=deployer)
    data = locking_token.approve.encode_input(voting_escrow, MAX_VALUE)
    proxy.call(locking_token, data, sender=deployer)
    proxy.set_operator(locker, True, sender=deployer)
    return locker

def test_initial_lock(ychad, alice, locking_token, voting_escrow, proxy, liquid_locker):
    locking_token.approve(liquid_locker, UNIT, sender=ychad)

    with ape.reverts():
        liquid_locker.deposit(UNIT, sender=alice)

    assert liquid_locker.totalSupply() == 0
    assert liquid_locker.balanceOf(alice) == 0
    assert voting_escrow.locked(proxy).amount == 0
    liquid_locker.deposit(UNIT, alice, sender=ychad)
    assert liquid_locker.totalSupply() == SCALE
    assert liquid_locker.balanceOf(alice) == SCALE
    assert voting_escrow.locked(proxy).amount == UNIT
    
def test_multiple_lock(ychad, alice, locking_token, voting_escrow, proxy, liquid_locker):
    locking_token.approve(liquid_locker, 3 * UNIT, sender=ychad)
    liquid_locker.deposit(UNIT, sender=ychad)
    liquid_locker.deposit(2 * UNIT, alice, sender=ychad)
    assert liquid_locker.totalSupply() == 3 * SCALE
    assert liquid_locker.balanceOf(alice) == 2 * SCALE
    assert voting_escrow.locked(proxy).amount == 3 * UNIT

def test_lock_extend(chain, ychad, locking_token, voting_escrow, proxy, liquid_locker):
    locking_token.approve(liquid_locker, 3 * UNIT, sender=ychad)
    liquid_locker.deposit(UNIT, sender=ychad)
    end = voting_escrow.locked(proxy).end
    assert end > 0
    chain.pending_timestamp += WEEK
    liquid_locker.deposit(2 * UNIT, sender=ychad)
    assert voting_escrow.locked(proxy).end > end

def test_manual_extend(chain, ychad, alice, locking_token, voting_escrow, proxy, liquid_locker):
    locking_token.approve(liquid_locker, UNIT, sender=ychad)
    liquid_locker.deposit(UNIT, sender=ychad)
    end = voting_escrow.locked(proxy).end
    assert end > 0
    chain.pending_timestamp += WEEK
    liquid_locker.extend_lock(sender=alice)
    assert voting_escrow.locked(proxy).end > end

def test_mint(ychad, alice, bob, locking_token, voting_escrow, proxy, liquid_locker):
    locking_token.approve(liquid_locker, 2 * UNIT, sender=ychad)
    liquid_locker.deposit(2 * UNIT, sender=ychad)
    locking_token.approve(voting_escrow, UNIT, sender=ychad)
    with ape.reverts():
        liquid_locker.mint(bob, sender=alice)
    voting_escrow.modify_lock(UNIT, 0, proxy, sender=ychad)
    liquid_locker.mint(bob, sender=alice)
    assert liquid_locker.balanceOf(bob) == SCALE
    with ape.reverts():
        liquid_locker.mint(bob, sender=alice)
