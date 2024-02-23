import ape
from pytest import fixture
from _constants import *

@fixture
def liquid_locker(project, deployer, yfi, veyfi, proxy):
    locker = project.LiquidLocker.deploy(yfi, veyfi, proxy, sender=deployer)
    data = yfi.approve.encode_input(veyfi, MAX_VALUE)
    proxy.call(yfi, data, sender=deployer)
    proxy.set_operator(locker, True, sender=deployer)
    return locker

def test_initial_lock(ychad, alice, yfi, veyfi, proxy, liquid_locker):
    yfi.approve(liquid_locker, UNIT, sender=ychad)

    with ape.reverts():
        liquid_locker.deposit(UNIT, sender=alice)

    assert liquid_locker.totalSupply() == 0
    assert liquid_locker.balanceOf(alice) == 0
    assert veyfi.locked(proxy).amount == 0
    liquid_locker.deposit(UNIT, alice, sender=ychad)
    assert liquid_locker.totalSupply() == UNIT
    assert liquid_locker.balanceOf(alice) == UNIT
    assert veyfi.locked(proxy).amount == UNIT
    
def test_multiple_lock(ychad, alice, yfi, veyfi, proxy, liquid_locker):
    yfi.approve(liquid_locker, 3 * UNIT, sender=ychad)
    liquid_locker.deposit(UNIT, sender=ychad)
    liquid_locker.deposit(2 * UNIT, alice, sender=ychad)
    assert liquid_locker.totalSupply() == 3 * UNIT
    assert liquid_locker.balanceOf(alice) == 2 * UNIT
    assert veyfi.locked(proxy).amount == 3 * UNIT

def test_lock_extend(chain, ychad, yfi, veyfi, proxy, liquid_locker):
    yfi.approve(liquid_locker, 3 * UNIT, sender=ychad)
    liquid_locker.deposit(UNIT, sender=ychad)
    end = veyfi.locked(proxy).end
    assert end > 0
    chain.pending_timestamp += WEEK
    liquid_locker.deposit(2 * UNIT, sender=ychad)
    assert veyfi.locked(proxy).end > end

def test_manual_extend(chain, ychad, alice, yfi, veyfi, proxy, liquid_locker):
    yfi.approve(liquid_locker, UNIT, sender=ychad)
    liquid_locker.deposit(UNIT, sender=ychad)
    end = veyfi.locked(proxy).end
    assert end > 0
    chain.pending_timestamp += WEEK
    liquid_locker.extend_lock(sender=alice)
    assert veyfi.locked(proxy).end > end

def test_mint(ychad, alice, bob, yfi, veyfi, proxy, liquid_locker):
    yfi.approve(liquid_locker, 2 * UNIT, sender=ychad)
    liquid_locker.deposit(2 * UNIT, sender=ychad)
    yfi.approve(veyfi, UNIT, sender=ychad)
    with ape.reverts():
        liquid_locker.mint(bob, sender=alice)
    veyfi.modify_lock(UNIT, 0, proxy, sender=ychad)
    liquid_locker.mint(bob, sender=alice)
    assert liquid_locker.balanceOf(bob) == UNIT
    with ape.reverts():
        liquid_locker.mint(bob, sender=alice)
