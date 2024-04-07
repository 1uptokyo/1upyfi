from ape import reverts
from pytest import fixture
from _constants import *

HARVEST_FEE_IDX     = 0 # harvest
FEE_IDX             = 1 # claim without redeem
REDEEM_SELL_FEE_IDX = 2 # claim with redeem, without ETH
REDEEM_FEE_IDX      = 3 # claim with redeem, with ETH
EXPECTED_DATA       = b"abcd"

@fixture
def token(project, deployer):
    return project.MockToken.deploy(sender=deployer)

@fixture
def registry(project, deployer):
    return project.MockRegistry.deploy(sender=deployer)

@fixture
def rewards(project, deployer, token, registry):
    return project.GaugeRewards.deploy(token, registry, sender=deployer)

@fixture
def ygauge(accounts):
    return accounts[3]

@fixture
def gauge(accounts, deployer, token, registry, rewards, ygauge):
    gauge = accounts[4]
    registry.set_gauge_map(ygauge, gauge, sender=deployer)
    token.approve(rewards, MAX_VALUE, sender=gauge)
    return gauge

@fixture
def redeem_token(project, deployer):
    return project.MockToken.deploy(sender=deployer)

@fixture
def redeemer(project, deployer, token, rewards, redeem_token):
    redeemer = project.MockGaugeRedeemer.deploy(token, redeem_token, sender=deployer)
    rewards.set_redeemer(redeemer, sender=deployer)
    return redeemer

def test_report_deposit(alice, rewards, ygauge, gauge):
    # deposit increases balance and supply
    assert rewards.gauge_supply(gauge) == 0
    assert rewards.gauge_balance(gauge, alice) == 0
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)
    assert rewards.gauge_supply(gauge) == UNIT
    assert rewards.gauge_balance(gauge, alice) == UNIT

def test_report_deposit_add(alice, rewards, ygauge, gauge):
    # deposits add to the balance and supply
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)
    rewards.report(ygauge, ZERO_ADDRESS, alice, 2 * UNIT, 0, sender=gauge)
    assert rewards.gauge_supply(gauge) == 3 * UNIT
    assert rewards.gauge_balance(gauge, alice) == 3 * UNIT

def test_report_deposit_multiple(alice, bob, rewards, ygauge, gauge):
    # deposits from different users are tracked correctly
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)
    rewards.report(ygauge, ZERO_ADDRESS, bob, 2 * UNIT, 0, sender=gauge)
    assert rewards.gauge_supply(gauge) == 3 * UNIT
    assert rewards.gauge_balance(gauge, alice) == UNIT
    assert rewards.gauge_balance(gauge, bob) == 2 * UNIT

def test_report_deposit_not_registered(deployer, alice, rewards, registry, ygauge, gauge):
    # gauge that is not registered cannot report a deposit
    registry.set_gauge_map(ygauge, ZERO_ADDRESS, sender=deployer)
    with reverts():
        rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)

def test_report_deposit_false(accounts, deployer, alice, rewards, registry, ygauge, gauge):
    # gauge of which the underlying is registered to another gauge cannot report a deposit
    registry.set_gauge_map(ygauge, accounts[5], sender=deployer)
    with reverts():
        rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)

def test_report_withdraw(alice, rewards, ygauge, gauge):
    # withdraw removes from balance and supply
    rewards.report(ygauge, ZERO_ADDRESS, alice, 3 * UNIT, 0, sender=gauge)
    rewards.report(ygauge, alice, ZERO_ADDRESS, UNIT, 0, sender=gauge)
    assert rewards.gauge_supply(gauge) == 2 * UNIT
    assert rewards.gauge_balance(gauge, alice) == 2 * UNIT

def test_report_withdraw_not_registered(deployer, alice, rewards, registry, ygauge, gauge):
    # can still withdraw after the gauge is unregistered
    rewards.report(ygauge, ZERO_ADDRESS, alice, 3 * UNIT, 0, sender=gauge)
    registry.set_gauge_map(ygauge, ZERO_ADDRESS, sender=deployer)
    rewards.report(ygauge, alice, ZERO_ADDRESS, UNIT, 0, sender=gauge)

def test_report_withdraw_excessive(alice, rewards, ygauge, gauge):
    # cant withdraw more than the balance
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)
    with reverts():
        rewards.report(ygauge, alice, ZERO_ADDRESS, 2 * UNIT, 0, sender=gauge)

def test_report_transfer(alice, bob, rewards, ygauge, gauge):
    # transfer changes balances but does not change supply
    rewards.report(ygauge, ZERO_ADDRESS, alice, 3 * UNIT, 0, sender=gauge)
    rewards.report(ygauge, alice, bob, UNIT, 0, sender=gauge)
    assert rewards.gauge_supply(gauge) == 3 * UNIT
    assert rewards.gauge_balance(gauge, alice) == 2 * UNIT
    assert rewards.gauge_balance(gauge, bob) == UNIT

def test_report_transfer_not_registered(deployer, alice, bob, rewards, registry, ygauge, gauge):
    # can still transfer after the gauge is unregistered
    rewards.report(ygauge, ZERO_ADDRESS, alice, 3 * UNIT, 0, sender=gauge)
    registry.set_gauge_map(ygauge, ZERO_ADDRESS, sender=deployer)
    rewards.report(ygauge, alice, bob, UNIT, 0, sender=gauge)

def test_report_transfer_excessive(alice, bob, rewards, ygauge, gauge):
    # cant withdraw more than the balance
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)
    with reverts():
        rewards.report(ygauge, alice, bob, 2 * UNIT, 0, sender=gauge)

def test_report_transfer_self(alice, rewards, ygauge, gauge):
    # cant transfer to self
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)
    with reverts():
        rewards.report(ygauge, alice, alice, UNIT, 0, sender=gauge)

def test_report_rewards(deployer, alice, token, rewards, ygauge, gauge):
    # rewards can be reported without a transfer
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)
    token.mint(gauge, 2 * UNIT, sender=deployer)
    rewards.report(ygauge, ZERO_ADDRESS, ZERO_ADDRESS, 0, 2 * UNIT, sender=gauge)
    assert token.balanceOf(rewards) == 2 * UNIT
    assert rewards.packed_balances(gauge, alice) >> 128 == 0
    assert rewards.pending(alice) == 0
    assert rewards.claimable(gauge, alice) == 2 * UNIT

def test_report_rewards(deployer, alice, token, rewards, registry, ygauge, gauge):
    # rewards can still be reported after the gauge is unregistered
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)
    registry.set_gauge_map(ygauge, ZERO_ADDRESS, sender=deployer)
    token.mint(gauge, 2 * UNIT, sender=deployer)
    rewards.report(ygauge, ZERO_ADDRESS, ZERO_ADDRESS, 0, 2 * UNIT, sender=gauge)

def test_report_rewards_excessive(deployer, alice, token, rewards, ygauge, gauge):
    # cant report more rewards than there actually are
    rewards.report(ygauge, ZERO_ADDRESS, alice, 2 * UNIT, 0, sender=gauge)
    token.mint(gauge, UNIT, sender=deployer)
    with reverts():
        rewards.report(ygauge, ZERO_ADDRESS, ZERO_ADDRESS, 0, 2 * UNIT, sender=gauge)

def test_report_deposit_rewards(deployer, alice, bob, token, rewards, ygauge, gauge):
    # rewards are synced before deposit is processed
    rewards.report(ygauge, ZERO_ADDRESS, alice, 2 * UNIT, 0, sender=gauge)
    token.mint(gauge, 6 * UNIT, sender=deployer)
    rewards.report(ygauge, ZERO_ADDRESS, bob, UNIT, 6 * UNIT, sender=gauge)
    assert token.balanceOf(rewards) == 6 * UNIT
    assert rewards.packed_supply(gauge) >> 128 == 3 * UNIT
    assert rewards.packed_balances(gauge, bob) >> 128 == 3 * UNIT
    assert rewards.pending(bob) == 0
    assert rewards.packed_balances(gauge, alice) >> 128 == 0
    assert rewards.pending(alice) == 0
    assert rewards.claimable(gauge, alice) == 6 * UNIT

def test_report_first_deposit_rewards(alice, token, rewards, ygauge, gauge):
    # rewards are not synced before first deposit
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, UNIT, sender=gauge)
    assert token.balanceOf(rewards) == 0
    assert rewards.packed_supply(gauge) >> 128 == 0

def test_report_withdraw_rewards(deployer, alice, bob, token, rewards, ygauge, gauge):
    # rewards are synced before withdraw is processed
    rewards.report(ygauge, ZERO_ADDRESS, alice, 2 * UNIT, 0, sender=gauge)
    rewards.report(ygauge, ZERO_ADDRESS, bob, UNIT, 0, sender=gauge)
    token.mint(gauge, 6 * UNIT, sender=deployer)
    rewards.report(ygauge, alice, ZERO_ADDRESS, 2 * UNIT, 6 * UNIT, sender=gauge)
    assert token.balanceOf(rewards) == 6 * UNIT
    assert rewards.packed_supply(gauge) >> 128 == 2 * UNIT
    assert rewards.packed_balances(gauge, alice) >> 128 == 2 * UNIT
    assert rewards.pending(alice) == 4 * UNIT
    assert rewards.claimable(gauge, alice) == 0
    assert rewards.packed_balances(gauge, bob) >> 128 == 0
    assert rewards.claimable(gauge, bob) == 2 * UNIT

def test_report_zero_transfer(deployer, token, rewards, ygauge, gauge):
    # cant report zero to zero address transfer
    token.mint(gauge, UNIT, sender=deployer)
    with reverts():
        rewards.report(ygauge, ZERO_ADDRESS, ZERO_ADDRESS, UNIT, 0, sender=gauge)

def test_report_zero_transfer_rewards(deployer, token, rewards, ygauge, gauge):
    # cant report zero to zero address transfer with rewards
    token.mint(gauge, UNIT, sender=deployer)
    with reverts():
        rewards.report(ygauge, ZERO_ADDRESS, ZERO_ADDRESS, UNIT, UNIT, sender=gauge)

def test_report_nothing(rewards, ygauge, gauge):
    # cant report nothing
    with reverts():
        rewards.report(ygauge, ZERO_ADDRESS, ZERO_ADDRESS, 0, 0, sender=gauge)

def test_harvest(deployer, alice, bob, token, rewards, ygauge, gauge):
    # harvest gauge rewards
    rewards.report(ygauge, ZERO_ADDRESS, alice, 2 * UNIT, 0, sender=gauge)
    token.mint(gauge, 6 * UNIT, sender=deployer)
    assert rewards.harvest([gauge], [6 * UNIT], sender=bob).return_value == 0
    assert token.balanceOf(rewards) == 6 * UNIT
    assert rewards.packed_supply(gauge) >> 128 == 3 * UNIT
    assert rewards.claimable(gauge, alice) == 6 * UNIT

def test_harvest_fee(deployer, alice, bob, token, rewards, ygauge, gauge):
    # harvest gauge rewards with harvest fee
    rewards.set_fee_rate(HARVEST_FEE_IDX, 2_500, sender=deployer)
    rewards.report(ygauge, ZERO_ADDRESS, alice, 2 * UNIT, 0, sender=gauge)
    token.mint(gauge, 8 * UNIT, sender=deployer)
    assert rewards.harvest([gauge], [8 * UNIT], bob, sender=alice).return_value == 2 * UNIT
    assert token.balanceOf(rewards) == 6 * UNIT
    assert token.balanceOf(bob) == 2 * UNIT
    assert rewards.packed_supply(gauge) >> 128 == 3 * UNIT
    assert rewards.claimable(gauge, alice) == 6 * UNIT

def test_harvest_excess(deployer, alice, token, rewards, ygauge, gauge):
    # cant harvest more than balance
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)
    token.mint(gauge, UNIT, sender=deployer)
    with reverts():
        rewards.harvest([gauge], [2 * UNIT], sender=deployer)

def test_harvest_no_supply(deployer, token, rewards, gauge):
    # a gauge without deposits wont get harvested
    rewards.set_fee_rate(HARVEST_FEE_IDX, 1_000, sender=deployer)
    token.mint(gauge, UNIT, sender=deployer)
    assert rewards.harvest([gauge], [UNIT], sender=deployer).return_value == 0
    assert token.balanceOf(gauge) == UNIT

def test_claim_naked(deployer, alice, bob, token, rewards, ygauge, gauge):
    # claim naked reward token
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)
    token.mint(gauge, 3 * UNIT, sender=deployer)
    rewards.harvest([gauge], [2 * UNIT], sender=deployer)
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)
    rewards.report(ygauge, ZERO_ADDRESS, bob, UNIT, UNIT, sender=gauge)
    assert rewards.pending(alice) == 2 * UNIT
    assert rewards.claimable(gauge, alice) == UNIT
    assert rewards.claim([gauge], bob, b"", sender=alice).return_value == 3 * UNIT
    assert rewards.pending(alice) == 0
    assert rewards.claimable(gauge, alice) == 0
    assert token.balanceOf(bob) == 3 * UNIT

def test_claim_naked_fee(deployer, alice, bob, token, rewards, ygauge, gauge):
    # claim naked reward token with fee
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)
    token.mint(gauge, 4 * UNIT, sender=deployer)
    rewards.harvest([gauge], [4 * UNIT], sender=deployer)
    rewards.set_fee_rate(FEE_IDX, 2_500, sender=deployer)
    assert rewards.claim([gauge], bob, b"", sender=alice).return_value == 3 * UNIT
    assert rewards.pending(alice) == 0
    assert rewards.claimable(gauge, alice) == 0
    assert token.balanceOf(bob) == 3 * UNIT
    assert rewards.pending_fees() == UNIT

def test_claim_redeem_sell(deployer, alice, bob, token, rewards, ygauge, gauge, redeem_token, redeemer):
    # claim with redeem, without ETH
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)
    token.mint(gauge, 3 * UNIT, sender=deployer)
    rewards.harvest([gauge], [3 * UNIT], sender=deployer)
    assert rewards.claim([gauge], bob, EXPECTED_DATA, sender=alice).return_value == 6 * UNIT
    assert rewards.pending(alice) == 0
    assert rewards.claimable(gauge, alice) == 0
    assert token.balanceOf(redeemer) == 3 * UNIT
    assert redeem_token.balanceOf(bob) == 6 * UNIT

def test_claim_redeem_sell_fee(deployer, alice, bob, token, rewards, ygauge, gauge, redeem_token, redeemer):
    # claim with redeem, without ETH, with fee
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)
    token.mint(gauge, 4 * UNIT, sender=deployer)
    rewards.harvest([gauge], [4 * UNIT], sender=deployer)
    rewards.set_fee_rate(FEE_IDX, 5_000, sender=deployer)
    rewards.set_fee_rate(REDEEM_SELL_FEE_IDX, 2_500, sender=deployer)
    assert rewards.claim([gauge], bob, EXPECTED_DATA, sender=alice).return_value == 6 * UNIT
    assert rewards.pending(alice) == 0
    assert rewards.claimable(gauge, alice) == 0
    assert token.balanceOf(redeemer) == 3 * UNIT
    assert redeem_token.balanceOf(bob) == 6 * UNIT
    assert rewards.pending_fees() == UNIT

def test_claim_redeem_eth(deployer, alice, bob, token, rewards, ygauge, gauge, redeem_token, redeemer):
    # claim with redeem, with ETH
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)
    token.mint(gauge, 3 * UNIT, sender=deployer)
    rewards.harvest([gauge], [3 * UNIT], sender=deployer)
    assert rewards.claim([gauge], bob, EXPECTED_DATA, value=UNIT, sender=alice).return_value == 7 * UNIT
    assert rewards.pending(alice) == 0
    assert rewards.claimable(gauge, alice) == 0
    assert token.balanceOf(redeemer) == 3 * UNIT
    assert redeem_token.balanceOf(bob) == 7 * UNIT
    assert redeemer.balance == UNIT

def test_claim_redeem_eth_fee(deployer, alice, bob, token, rewards, ygauge, gauge, redeem_token, redeemer):
    # claim with redeem, with ETH, with fee
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)
    token.mint(gauge, 4 * UNIT, sender=deployer)
    rewards.harvest([gauge], [4 * UNIT], sender=deployer)
    rewards.set_fee_rate(FEE_IDX, 5_000, sender=deployer)
    rewards.set_fee_rate(REDEEM_SELL_FEE_IDX, 5_000, sender=deployer)
    rewards.set_fee_rate(REDEEM_FEE_IDX, 2_500, sender=deployer)
    assert rewards.claim([gauge], bob, EXPECTED_DATA, value=UNIT, sender=alice).return_value == 7 * UNIT
    assert rewards.pending(alice) == 0
    assert rewards.claimable(gauge, alice) == 0
    assert token.balanceOf(redeemer) == 3 * UNIT
    assert redeem_token.balanceOf(bob) == 7 * UNIT
    assert redeemer.balance == UNIT
    assert rewards.pending_fees() == UNIT

def test_claim_redeem_no_redeemer(deployer, alice, bob, token, rewards, ygauge, gauge, redeem_token, redeemer):
    # cant redeem without a redeemer set
    rewards.set_redeemer(ZERO_ADDRESS, sender=deployer)
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)
    token.mint(gauge, 3 * UNIT, sender=deployer)
    rewards.harvest([gauge], [3 * UNIT], sender=deployer)
    with reverts():
        rewards.claim([gauge], bob, EXPECTED_DATA, sender=alice)

def test_set_fee_rate(deployer, rewards):
    # fee rates are stored properly
    v = 1_000
    for i in range(4):
        assert rewards.fee_rates(i) == 0
        rewards.set_fee_rate(i, v + i, sender=deployer)
    for i in range(4):
        assert rewards.fee_rates(i) == v + i

def test_set_fee_rate_max(deployer, rewards):
    # cant set fee of more than 100%
    with reverts():
        rewards.set_fee_rate(0, 10_001, sender=deployer)

def test_set_fee_rate_invalid_index(deployer, rewards):
    # cant set fee for invalid index
    with reverts():
        rewards.set_fee_rate(4, 1_000, sender=deployer)

def test_set_fee_rate_permission(alice, rewards):
    # only management can set fees
    with reverts():
        rewards.set_fee_rate(0, 1_000, sender=alice)

def test_pending_fees(deployer, alice, token, rewards, ygauge, gauge):
    # fees add up properly and dont write the other fields
    for i in range(4):
        # make our lives easier, set naked claim fee to 25%
        rewards.set_fee_rate(i, 2_500 + i - FEE_IDX, sender=deployer)
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)
    token.mint(gauge, 4 * UNIT, sender=deployer)
    rewards.report(ygauge, ZERO_ADDRESS, ZERO_ADDRESS, 0, 4 * UNIT, sender=gauge)
    rewards.claim([gauge], sender=alice)
    token.mint(gauge, 8 * UNIT, sender=deployer)
    rewards.report(ygauge, ZERO_ADDRESS, ZERO_ADDRESS, 0, 8 * UNIT, sender=gauge)
    rewards.claim([gauge], sender=alice)
    assert rewards.pending_fees() == 3 * UNIT
    for i in range(4):
        rewards.fee_rates(i) == 2_500 + i - FEE_IDX

def test_claim_fees(deployer, alice, bob, token, rewards, ygauge, gauge):
    # claimed fees are sent to treasury
    rewards.set_treasury(bob, sender=deployer)
    rewards.report(ygauge, ZERO_ADDRESS, alice, UNIT, 0, sender=gauge)
    token.mint(gauge, 4 * UNIT, sender=deployer)
    rewards.harvest([gauge], [4 * UNIT], sender=deployer)
    rewards.set_fee_rate(FEE_IDX, 2_500, sender=deployer)
    rewards.claim([gauge], sender=alice)
    assert rewards.pending_fees() == UNIT
    rewards.claim_fees(sender=alice)
    assert rewards.pending_fees() == 0
    assert token.balanceOf(bob) == UNIT

def test_set_redeemer(project, deployer, token, rewards, redeem_token, redeemer):
    # setting new redeemer retracts previous allowance and sets a new one
    redeemer2 = project.MockGaugeRedeemer.deploy(token, redeem_token, sender=deployer)
    assert rewards.redeemer() == redeemer
    assert token.allowance(rewards, redeemer) == MAX_VALUE
    assert token.allowance(rewards, redeemer2) == 0
    rewards.set_redeemer(redeemer2, sender=deployer)
    assert token.allowance(rewards, redeemer) == 0
    assert token.allowance(rewards, redeemer2) == MAX_VALUE

def test_set_no_redeemer(deployer, token, rewards, redeemer):
    # redeemer can be cleared, effectively disabling redemptions
    assert rewards.redeemer() == redeemer
    assert token.allowance(rewards, redeemer) == MAX_VALUE
    rewards.set_redeemer(ZERO_ADDRESS, sender=deployer)
    assert token.allowance(rewards, redeemer) == 0

def test_set_redeemer_permission(project, deployer, alice, token, rewards, redeem_token):
    # only management can set a new redeemer
    redeemer2 = project.MockGaugeRedeemer.deploy(token, redeem_token, sender=deployer)
    with reverts():
        rewards.set_redeemer(redeemer2, sender=alice)

def test_set_treasury(deployer, alice, rewards):
    # fee recipient can be changed
    assert rewards.treasury() == deployer
    rewards.set_treasury(alice, sender=deployer)
    assert rewards.treasury() == alice

def test_set_treasury_permission(alice, rewards):
    # only management can change fee recipient
    with reverts():
        rewards.set_treasury(alice, sender=alice)

def test_set_management(deployer, alice, rewards):
    # management can propose a replacement
    assert rewards.management() == deployer
    assert rewards.pending_management() == ZERO_ADDRESS
    rewards.set_management(alice, sender=deployer)
    assert rewards.management() == deployer
    assert rewards.pending_management() == alice

def test_set_management_undo(deployer, alice, rewards):
    # proposed replacement can be undone
    rewards.set_management(alice, sender=deployer)
    rewards.set_management(ZERO_ADDRESS, sender=deployer)
    assert rewards.management() == deployer
    assert rewards.pending_management() == ZERO_ADDRESS

def test_set_management_permission(alice, rewards):
    # only management can propose a replacement
    with reverts():
        rewards.set_management(alice, sender=alice)

def test_accept_management(deployer, alice, rewards):
    # replacement can accept management role
    rewards.set_management(alice, sender=deployer)
    rewards.accept_management(sender=alice)
    assert rewards.management() == alice
    assert rewards.pending_management() == ZERO_ADDRESS

def test_accept_management_early(alice, rewards):
    # cant accept management role without being nominated
    with reverts():
        rewards.accept_management(sender=alice)

def test_accept_management_wrong(deployer, alice, bob, rewards):
    # cant accept management role without being the nominee
    rewards.set_management(alice, sender=deployer)
    with reverts():
        rewards.accept_management(sender=bob)
