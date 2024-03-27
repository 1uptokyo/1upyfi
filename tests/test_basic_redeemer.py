from ape import reverts
from ape import Contract
from pytest import fixture
from eth_abi import encode
from _constants import *

@fixture
def rewards(accounts):
    return accounts[3]

@fixture
def yearn_redemption():
    return Contract(REDEMPTION)

@fixture
def curve_pool():
    return Contract(DYFI_CURVE)

@fixture
def redeemer(
    project, deployer, ychad, locking_token, discount_token, voting_escrow, 
    proxy, liquid_locker, rewards, yearn_redemption, curve_pool):

    locking_token.approve(liquid_locker, UNIT, sender=ychad)
    liquid_locker.deposit(UNIT, sender=ychad)

    redeemer = project.BasicRedeemer.deploy(
        voting_escrow, liquid_locker, locking_token, discount_token, 
        proxy, rewards, ZERO_ADDRESS, sender=deployer
    )
    redeemer.set_yearn_redemption(yearn_redemption, sender=deployer)
    redeemer.set_curve_pool(curve_pool, sender=deployer)
    return redeemer

def test_redeem_discount_eth(accounts, alice, bob, liquid_locker, rewards, discount_token, yearn_redemption, redeemer):
    # redeem with ETH
    discount_token.mint(rewards, UNIT, sender=accounts[discount_token.owner()])
    discount_token.approve(redeemer, UNIT, sender=rewards)
    value = yearn_redemption.eth_required(UNIT)

    assert discount_token.balanceOf(rewards) == UNIT
    assert liquid_locker.totalSupply() == SCALE
    assert liquid_locker.balanceOf(bob) == 0
    assert redeemer.balance == 0
    redeemer.redeem(alice, bob, 0, UNIT, b"", value=value, sender=rewards)
    assert discount_token.balanceOf(rewards) == 0
    assert liquid_locker.totalSupply() == 2 * SCALE
    assert liquid_locker.balanceOf(bob) == SCALE
    assert redeemer.balance > 0

def test_redeem_discount_eth_slippage(accounts, alice, bob, liquid_locker, rewards, discount_token, yearn_redemption, redeemer):
    # redeem with an excessive amount of ETH, it should send the excess to the receiver
    discount_token.mint(rewards, UNIT, sender=accounts[discount_token.owner()])
    discount_token.approve(redeemer, UNIT, sender=rewards)
    value = yearn_redemption.eth_required(UNIT) + UNIT

    assert discount_token.balanceOf(rewards) == UNIT
    assert liquid_locker.totalSupply() == SCALE
    assert liquid_locker.balanceOf(bob) == 0
    assert redeemer.balance == 0
    pre_bal = bob.balance
    redeemer.redeem(alice, bob, 0, UNIT, b"", value=value, sender=rewards)
    assert discount_token.balanceOf(rewards) == 0
    assert liquid_locker.totalSupply() == 2 * SCALE
    assert liquid_locker.balanceOf(bob) == SCALE
    assert redeemer.balance > 0
    assert bob.balance - pre_bal >= UNIT

def test_redeem_discount_eth_lt(accounts, alice, bob, ychad, locking_token, liquid_locker, rewards, discount_token, yearn_redemption, redeemer):
    # redeem with ETH, with locking token rewards
    discount_token.mint(rewards, UNIT, sender=accounts[discount_token.owner()])
    discount_token.approve(redeemer, UNIT, sender=rewards)
    value = yearn_redemption.eth_required(UNIT)
    locking_token.transfer(rewards, 2 * UNIT, sender=ychad)
    locking_token.approve(redeemer, 2 * UNIT, sender=rewards)

    assert discount_token.balanceOf(rewards) == UNIT
    assert locking_token.balanceOf(rewards) == 2 * UNIT
    assert liquid_locker.totalSupply() == SCALE
    assert liquid_locker.balanceOf(bob) == 0
    assert redeemer.balance == 0
    redeemer.redeem(alice, bob, 2 * UNIT, UNIT, b"", value=value, sender=rewards)
    assert discount_token.balanceOf(rewards) == 0
    assert locking_token.balanceOf(rewards) == 0
    assert liquid_locker.totalSupply() == 4 * SCALE
    assert liquid_locker.balanceOf(bob) == 3 * SCALE
    assert redeemer.balance > 0

def test_redeem_discount_sell(accounts, alice, bob, liquid_locker, rewards, discount_token, curve_pool, redeemer):
    # redeem without ETH (sell rewards)
    discount_token.mint(rewards, UNIT, sender=accounts[discount_token.owner()])
    discount_token.approve(redeemer, UNIT, sender=rewards)
    data = encode(['uint256'], [2 * UNIT // 10]) # sell 0.2 discount token
    before = discount_token.balanceOf(curve_pool)

    assert discount_token.balanceOf(rewards) == UNIT
    assert liquid_locker.totalSupply() == SCALE
    assert liquid_locker.balanceOf(bob) == 0
    assert redeemer.balance == 0
    redeemer.redeem(alice, bob, 0, UNIT, data, sender=rewards)
    assert discount_token.balanceOf(rewards) == 0
    assert discount_token.balanceOf(curve_pool) > before
    assert liquid_locker.totalSupply() == 18 * SCALE // 10
    assert liquid_locker.balanceOf(bob) == 8 * SCALE // 10
    assert redeemer.balance > 0

def test_redeem_discount_sell_lt(accounts, alice, bob, ychad, locking_token, liquid_locker, rewards, discount_token, curve_pool, redeemer):
    # redeem without ETH (sell rewards), with locking token rewards
    discount_token.mint(rewards, UNIT, sender=accounts[discount_token.owner()])
    discount_token.approve(redeemer, UNIT, sender=rewards)
    locking_token.transfer(rewards, 2 * UNIT, sender=ychad)
    locking_token.approve(redeemer, 2 * UNIT, sender=rewards)
    data = encode(['uint256'], [2 * UNIT // 10]) # sell 0.2 discount token
    before = discount_token.balanceOf(curve_pool)

    assert discount_token.balanceOf(rewards) == UNIT
    assert locking_token.balanceOf(rewards) == 2 * UNIT
    assert liquid_locker.totalSupply() == SCALE
    assert liquid_locker.balanceOf(bob) == 0
    assert redeemer.balance == 0
    redeemer.redeem(alice, bob, 2 * UNIT, UNIT, data, sender=rewards)
    assert discount_token.balanceOf(rewards) == 0
    assert discount_token.balanceOf(curve_pool) > before
    assert locking_token.balanceOf(rewards) == 0
    assert liquid_locker.totalSupply() == 38 * SCALE // 10
    assert liquid_locker.balanceOf(bob) == 28 * SCALE // 10
    assert redeemer.balance > 0

def test_claim_excess(accounts, deployer, alice, bob, rewards, discount_token, yearn_redemption, redeemer):
    # excess is sent to treasury
    redeemer.set_treasury(alice, sender=deployer)
    discount_token.mint(rewards, UNIT, sender=accounts[discount_token.owner()])
    discount_token.approve(redeemer, UNIT, sender=rewards)
    value = yearn_redemption.eth_required(UNIT)
    redeemer.redeem(alice, bob, 0, UNIT, b"", value=value, sender=rewards)
    before = alice.balance
    redeemer.claim_excess(sender=bob)
    assert alice.balance > before

def test_set_treasury(deployer, alice, redeemer):
    # change treasury
    assert redeemer.treasury() == deployer
    redeemer.set_treasury(alice, sender=deployer)
    assert redeemer.treasury() == alice

def test_set_treasury_permission(alice, redeemer):
    # only management can change treasury
    with reverts():
        redeemer.set_treasury(alice, sender=alice)

def test_set_yearn_redemption(accounts, deployer, discount_token, redeemer, yearn_redemption):
    # discount token redemption contract can be changed
    new_redemption = accounts[4]
    assert redeemer.yearn_redemption() == yearn_redemption
    assert discount_token.allowance(redeemer, yearn_redemption) == MAX_VALUE
    assert discount_token.allowance(redeemer, new_redemption) == 0
    redeemer.set_yearn_redemption(new_redemption, sender=deployer)
    assert redeemer.yearn_redemption() == new_redemption
    assert discount_token.allowance(redeemer, yearn_redemption) == 0
    assert discount_token.allowance(redeemer, new_redemption) == MAX_VALUE

def test_unset_yearn_redemption(deployer, discount_token, redeemer, yearn_redemption):
    # discount token redemption contract can be unset, effectively disabling all redemptions
    redeemer.set_yearn_redemption(ZERO_ADDRESS, sender=deployer)
    assert redeemer.yearn_redemption() == ZERO_ADDRESS
    assert discount_token.allowance(redeemer, yearn_redemption) == 0
    assert discount_token.allowance(redeemer, ZERO_ADDRESS) == 0

def test_set_yearn_redemption_permission(accounts, alice, redeemer):
    # only management can set redemption contract
    with reverts():
        redeemer.set_yearn_redemption(accounts[4], sender=alice)

def test_set_curve_pool(accounts, deployer, discount_token, redeemer, curve_pool):
    # discount token curve pool can be changed
    new_pool = accounts[4]
    assert redeemer.curve_pool() == curve_pool
    assert discount_token.allowance(redeemer, curve_pool) == MAX_VALUE
    assert discount_token.allowance(redeemer, new_pool) == 0
    redeemer.set_curve_pool(new_pool, sender=deployer)
    assert redeemer.curve_pool() == new_pool
    assert discount_token.allowance(redeemer, curve_pool) == 0
    assert discount_token.allowance(redeemer, new_pool) == MAX_VALUE

def test_unset_curve_pool(deployer, discount_token, redeemer, curve_pool):
    # discount token curve pool can be unset, effectively disabling redemptions without sending ETH
    redeemer.set_curve_pool(ZERO_ADDRESS, sender=deployer)
    assert redeemer.curve_pool() == ZERO_ADDRESS
    assert discount_token.allowance(redeemer, curve_pool) == 0
    assert discount_token.allowance(redeemer, ZERO_ADDRESS) == 0

def test_set_curve_pool_permission(accounts, alice, redeemer):
    # only management can set the curve pool
    with reverts():
        redeemer.set_curve_pool(accounts[4], sender=alice)

def test_set_management(deployer, alice, redeemer):
    # management can propose a replacement
    assert redeemer.management() == deployer
    assert redeemer.pending_management() == ZERO_ADDRESS
    redeemer.set_management(alice, sender=deployer)
    assert redeemer.management() == deployer
    assert redeemer.pending_management() == alice

def test_set_management_undo(deployer, alice, redeemer):
    # proposed replacement can be undone
    redeemer.set_management(alice, sender=deployer)
    redeemer.set_management(ZERO_ADDRESS, sender=deployer)
    assert redeemer.management() == deployer
    assert redeemer.pending_management() == ZERO_ADDRESS

def test_set_management_permission(alice, redeemer):
    # only management can propose a replacement
    with reverts():
        redeemer.set_management(alice, sender=alice)

def test_accept_management(deployer, alice, redeemer):
    # replacement can accept management role
    redeemer.set_management(alice, sender=deployer)
    redeemer.accept_management(sender=alice)
    assert redeemer.management() == alice
    assert redeemer.pending_management() == ZERO_ADDRESS

def test_accept_management_early(alice, redeemer):
    # cant accept management role without being nominated
    with reverts():
        redeemer.accept_management(sender=alice)

def test_accept_management_wrong(deployer, alice, bob, redeemer):
    # cant accept management role without being the nominee
    redeemer.set_management(alice, sender=deployer)
    with reverts():
        redeemer.accept_management(sender=bob)
