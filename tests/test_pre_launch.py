import ape
from pytest import fixture
from _constants import *

@fixture
def liquid_locker(project, deployer, yfi, veyfi, proxy):
    locker = project.YearnLiquidLocker.deploy(yfi, veyfi, proxy, sender=deployer)
    data = yfi.approve.encode_input(veyfi, MAX_VALUE)
    proxy.call(yfi, data, sender=deployer)
    proxy.set_operator(locker, True, sender=deployer)
    return locker

@fixture
def pre_launch(chain, project, deployer, yfi, liquid_locker):
    ts = chain.pending_timestamp + WEEK
    return project.PreLaunchDeposit.deploy(yfi, liquid_locker, 10 * UNIT, ts, deployer, sender=deployer)

def test_deposit(ychad, alice, bob, yfi, pre_launch):
    yfi.transfer(alice, 3 * UNIT, sender=ychad)
    yfi.approve(pre_launch, 2 * UNIT, sender=alice)

    # deposit
    assert pre_launch.deposited() == 0
    assert pre_launch.deposits(alice) == 0
    pre_launch.deposit(2 * UNIT, sender=alice)
    assert pre_launch.deposited() == 2 * UNIT
    assert pre_launch.deposits(alice) == 2 * UNIT
    assert yfi.balanceOf(alice) == UNIT
    assert yfi.balanceOf(pre_launch) == 2 * UNIT

    # deposit from second account
    yfi.transfer(bob, 4 * UNIT, sender=ychad)
    yfi.approve(pre_launch, 4 * UNIT, sender=bob)
    pre_launch.deposit(UNIT, sender=bob)
    assert pre_launch.deposited() == 3 * UNIT
    assert pre_launch.deposits(bob) == UNIT
    assert yfi.balanceOf(pre_launch) == 3 * UNIT

    # deposit on behalf of someone else
    pre_launch.deposit(3 * UNIT, alice, sender=bob)
    assert pre_launch.deposited() == 6 * UNIT
    assert pre_launch.deposits(alice) == 5 * UNIT
    assert pre_launch.deposits(bob) == UNIT
    assert yfi.balanceOf(pre_launch) == 6 * UNIT

def test_deposit_deadline(chain, ychad, alice, yfi, pre_launch):
    yfi.transfer(alice, UNIT, sender=ychad)
    yfi.approve(pre_launch, UNIT, sender=alice)

    # can deposit
    with chain.isolate():
        pre_launch.deposit(UNIT, sender=alice)

    # cant deposit after deadline
    chain.pending_timestamp += WEEK
    with ape.reverts('deadline passed'):
        pre_launch.deposit(UNIT, sender=alice)

def test_refund(chain, ychad, deployer, alice, bob, yfi, pre_launch):
    yfi.transfer(alice, 3 * UNIT, sender=ychad)
    yfi.approve(pre_launch, 3 * UNIT, sender=alice)
    pre_launch.deposit(UNIT, sender=alice)
    pre_launch.deposit(2 * UNIT, bob, sender=alice)

    # cant refund early
    with ape.reverts():
        pre_launch.refund(sender=alice)

    # cant activate
    chain.pending_timestamp += WEEK
    with ape.reverts():
        pre_launch.activate(sender=deployer)

    assert pre_launch.deposited() == 3 * UNIT
    assert pre_launch.deposits(alice) == UNIT
    assert pre_launch.deposits(bob) == 2 * UNIT
    assert yfi.balanceOf(alice) == 0
    assert yfi.balanceOf(bob) == 0
    assert yfi.balanceOf(pre_launch) == 3 * UNIT

    # refund
    pre_launch.refund(sender=alice)
    assert pre_launch.deposited() == 2 * UNIT
    assert pre_launch.deposits(alice) == 0
    assert yfi.balanceOf(alice) == UNIT
    assert yfi.balanceOf(pre_launch) == 2 * UNIT

    # cant double refund
    with ape.reverts():
        pre_launch.refund(sender=alice)

    # refund on behalf of someone else
    pre_launch.refund(bob, sender=alice)
    assert pre_launch.deposited() == 0
    assert pre_launch.deposits(bob) == 0
    assert yfi.balanceOf(bob) == 2 * UNIT
    assert yfi.balanceOf(pre_launch) == 0

def test_refund_not_activated(chain, ychad, alice, yfi, pre_launch):
    yfi.transfer(alice, 10 * UNIT, sender=ychad)
    yfi.approve(pre_launch, 10 * UNIT, sender=alice)
    pre_launch.deposit(10 * UNIT, sender=alice)

    chain.pending_timestamp += WEEK
    chain.mine()

    # cant refund yet because threshold has been met
    with ape.reverts():
        pre_launch.refund(sender=alice)

    # refund after activation deadline
    chain.pending_timestamp += 2 * WEEK
    pre_launch.refund(sender=alice)
    assert yfi.balanceOf(alice) == 10 * UNIT

def test_activate(chain, ychad, deployer, alice, yfi, veyfi, proxy, liquid_locker, pre_launch):
    yfi.transfer(alice, 10 * UNIT, sender=ychad)
    yfi.approve(pre_launch, 10 * UNIT, sender=alice)
    pre_launch.deposit(10 * UNIT, sender=alice)

    # cant activate early
    with ape.reverts():
        pre_launch.activate(sender=deployer)

    assert veyfi.locked(proxy).amount == 0
    assert liquid_locker.totalSupply() == 0
    assert liquid_locker.balanceOf(pre_launch) == 0

    # cant activate without permission
    chain.pending_timestamp += WEEK
    with ape.reverts():
        pre_launch.activate(sender=alice)

    # activate
    pre_launch.activate(sender=deployer)
    assert veyfi.locked(proxy).amount == 10 * UNIT
    assert liquid_locker.totalSupply() == 10 * UNIT
    assert liquid_locker.balanceOf(pre_launch) == 10 * UNIT

    # cant double activate
    with ape.reverts():
        pre_launch.activate(sender=deployer)

def test_activate_late(chain, ychad, deployer, alice, yfi, veyfi, proxy, liquid_locker, pre_launch):
    yfi.transfer(alice, 10 * UNIT, sender=ychad)
    yfi.approve(pre_launch, 10 * UNIT, sender=alice)
    pre_launch.deposit(10 * UNIT, sender=alice)

    # cant activate late
    chain.pending_timestamp += 3 * WEEK
    with ape.reverts():
        pre_launch.activate(sender=deployer)

def test_claim(chain, ychad, deployer, alice, bob, yfi, liquid_locker, pre_launch):
    yfi.transfer(alice, 10 * UNIT, sender=ychad)
    yfi.approve(pre_launch, 10 * UNIT, sender=alice)
    pre_launch.deposit(6 * UNIT, sender=alice)
    pre_launch.deposit(4 * UNIT, bob, sender=alice)

    # cant claim early
    with ape.reverts():
        pre_launch.claim(sender=alice)

    # activate
    chain.pending_timestamp += WEEK
    pre_launch.activate(sender=deployer)

    # cant refund after activating
    with ape.reverts():
        pre_launch.refund(sender=alice)

    assert not pre_launch.claimed(alice)
    assert liquid_locker.balanceOf(alice) == 0
    assert liquid_locker.balanceOf(pre_launch) == 10 * UNIT

    # claim
    pre_launch.claim(sender=alice)
    assert pre_launch.claimed(alice)
    assert liquid_locker.balanceOf(alice) == 6 * UNIT
    assert liquid_locker.balanceOf(pre_launch) == 4 * UNIT

    # cant double claim
    with ape.reverts():
        pre_launch.claim(sender=alice)

    # claim on behalf of someone else
    assert liquid_locker.balanceOf(bob) == 0
    pre_launch.claim(bob, sender=alice)
    assert liquid_locker.balanceOf(bob) == 4 * UNIT
    assert liquid_locker.balanceOf(pre_launch) == 0
