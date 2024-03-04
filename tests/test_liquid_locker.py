from ape import reverts
from _constants import *

def test_deposit_initial(ychad, alice, locking_token, voting_escrow, proxy, liquid_locker):
    # initial deposit creates the lock
    locking_token.approve(liquid_locker, UNIT, sender=ychad)
    assert liquid_locker.totalSupply() == 0
    assert liquid_locker.balanceOf(alice) == 0
    assert voting_escrow.locked(proxy).amount == 0
    liquid_locker.deposit(UNIT, alice, sender=ychad)
    assert liquid_locker.totalSupply() == SCALE
    assert liquid_locker.balanceOf(alice) == SCALE
    assert voting_escrow.locked(proxy).amount == UNIT
    
def test_deposit_multiple(ychad, alice, locking_token, voting_escrow, proxy, liquid_locker):
    # multiple deposits are accounted for properly
    locking_token.approve(liquid_locker, 3 * UNIT, sender=ychad)
    liquid_locker.deposit(UNIT, sender=ychad)
    liquid_locker.deposit(2 * UNIT, alice, sender=ychad)
    assert liquid_locker.totalSupply() == 3 * SCALE
    assert liquid_locker.balanceOf(alice) == 2 * SCALE
    assert voting_escrow.locked(proxy).amount == 3 * UNIT

def test_mint(ychad, alice, bob, locking_token, voting_escrow, proxy, liquid_locker):
    # mint any lock amount that is not yet tokenized
    locking_token.approve(liquid_locker, 2 * UNIT, sender=ychad)
    liquid_locker.deposit(2 * UNIT, sender=ychad)

    locking_token.approve(voting_escrow, 3 * UNIT, sender=ychad)
    voting_escrow.modify_lock(3 * UNIT, 0, proxy, sender=ychad)
    liquid_locker.mint(bob, sender=alice)
    assert liquid_locker.totalSupply() == 5 * SCALE
    assert liquid_locker.balanceOf(bob) == 3 * SCALE

def test_mint_no_excess(ychad, alice, bob, locking_token, voting_escrow, liquid_locker):
    # cant mint without any excess
    locking_token.approve(liquid_locker, 2 * UNIT, sender=ychad)
    liquid_locker.deposit(2 * UNIT, sender=ychad)
    locking_token.approve(voting_escrow, UNIT, sender=ychad)
    with reverts():
        liquid_locker.mint(bob, sender=alice)

def test_lock_extend(chain, ychad, locking_token, voting_escrow, proxy, liquid_locker):
    # depositing automatically extends the lock
    locking_token.approve(liquid_locker, 3 * UNIT, sender=ychad)
    liquid_locker.deposit(UNIT, sender=ychad)
    end = voting_escrow.locked(proxy).end
    assert end > 0
    chain.pending_timestamp += WEEK
    liquid_locker.deposit(2 * UNIT, sender=ychad)
    assert voting_escrow.locked(proxy).end > end

def test_manual_extend(chain, ychad, alice, locking_token, voting_escrow, proxy, liquid_locker):
    # anyone can manually extend the lock
    locking_token.approve(liquid_locker, UNIT, sender=ychad)
    liquid_locker.deposit(UNIT, sender=ychad)
    end = voting_escrow.locked(proxy).end
    assert end > 0
    chain.pending_timestamp += WEEK
    liquid_locker.extend_lock(sender=alice)
    assert voting_escrow.locked(proxy).end > end

def test_transfer(ychad, alice, locking_token, liquid_locker):
    # transfer liquid locker token
    locking_token.approve(liquid_locker, 3 * UNIT, sender=ychad)
    liquid_locker.deposit(3 * UNIT, sender=ychad)
    liquid_locker.transfer(alice, SCALE, sender=ychad)
    assert liquid_locker.totalSupply() == 3 * SCALE
    assert liquid_locker.balanceOf(ychad) == 2 * SCALE
    assert liquid_locker.balanceOf(alice) == SCALE

def test_transfer_more(ychad, alice, locking_token, liquid_locker):
    # cant transfer more than balance
    locking_token.approve(liquid_locker, UNIT, sender=ychad)
    liquid_locker.deposit(UNIT, sender=ychad)
    with reverts():
        liquid_locker.transfer(alice, 2 * SCALE, sender=ychad)

def test_approve(alice, bob, liquid_locker):
    # approve another user to spend liquid locker token
    assert liquid_locker.allowance(alice, bob) == 0
    liquid_locker.approve(bob, UNIT, sender=alice)
    assert liquid_locker.allowance(alice, bob) == UNIT

def test_transfer_from(ychad, alice, bob, locking_token, liquid_locker):
    # transfer liquid locker token using allowance
    locking_token.approve(liquid_locker, 3 * UNIT, sender=ychad)
    liquid_locker.deposit(3 * UNIT, sender=ychad)
    liquid_locker.approve(alice, 5 * SCALE, sender=ychad)
    liquid_locker.transferFrom(ychad, bob, SCALE, sender=alice)
    assert liquid_locker.totalSupply() == 3 * SCALE
    assert liquid_locker.balanceOf(ychad) == 2 * SCALE
    assert liquid_locker.balanceOf(bob) == SCALE
    assert liquid_locker.allowance(ychad, alice) == 4 * SCALE

def test_transfer_from_more(ychad, alice, bob, locking_token, liquid_locker):
    # cant transfer more than allowance
    locking_token.approve(liquid_locker, 3 * UNIT, sender=ychad)
    liquid_locker.deposit(3 * UNIT, sender=ychad)
    liquid_locker.approve(alice, SCALE, sender=ychad)
    with reverts():
        liquid_locker.transferFrom(ychad, bob, 2 * SCALE, sender=alice)
