from ape import reverts, Contract
# from ape_ethereum.proxies import _make_minimal_proxy
from ape.contracts import ContractContainer
from pytest import fixture
from _constants import *

@fixture
def yvault(project, deployer):
    return project.MockToken.deploy(sender=deployer)

@fixture
def ygauge(networks, deployer, yvault):
    ygauge_mainnet = Contract(YGAUGE)
    ygauge = '0x0123456789012345678901234567890123456789'
    networks.active_provider.set_code(ygauge, networks.active_provider.get_code(YGAUGE))
    ygauge = Contract(ygauge, ygauge_mainnet.contract_type)
    ygauge.initialize(yvault, deployer, sender=deployer)
    return ygauge

@fixture
def reward_token(project, deployer):
    return project.MockToken.deploy(sender=deployer)

@fixture
def registry(project, deployer):
    return project.MockRegistry.deploy(sender=deployer)

@fixture
def rewards(project, deployer, reward_token, registry):
    return project.GaugeRewards.deploy(reward_token, registry, sender=deployer)

@fixture
def gauge(project, deployer, proxy, ygauge, reward_token, registry, rewards):
    gauge = project.Gauge.deploy(ygauge, proxy, reward_token, rewards, sender=deployer)
    registry.set_gauge_map(ygauge, gauge, sender=deployer)
    data = ygauge.approve.encode_input(gauge, MAX_VALUE)
    proxy.call(ygauge, data, sender=deployer) # done by registry upon registration
    return gauge

def test_deposit(deployer, alice, bob, proxy, yvault, ygauge, rewards, gauge):
    # depositing increases supply and user balance
    yvault.mint(alice, UNIT, sender=deployer)
    yvault.approve(gauge, UNIT, sender=alice)
    assert yvault.balanceOf(ygauge) == 0
    assert ygauge.balanceOf(proxy) == 0
    assert ygauge.balanceOf(proxy) == 0
    assert rewards.gauge_supply(gauge) == 0
    assert rewards.gauge_balance(gauge, bob) == 0
    assert gauge.totalSupply() == 0
    assert gauge.balanceOf(bob) == 0
    gauge.deposit(UNIT, bob, sender=alice)
    assert yvault.balanceOf(ygauge) == UNIT
    assert ygauge.balanceOf(proxy) == UNIT
    assert rewards.gauge_supply(gauge) == UNIT
    assert rewards.gauge_balance(gauge, bob) == UNIT
    assert gauge.totalSupply() == UNIT
    assert gauge.balanceOf(bob) == UNIT

def test_deposit_add(deployer, alice, proxy, yvault, ygauge, rewards, gauge):
    # depositing adds to supply and user balance
    yvault.mint(alice, 3 * UNIT, sender=deployer)
    yvault.approve(gauge, 3 * UNIT, sender=alice)
    gauge.deposit(UNIT, sender=alice)
    gauge.deposit(2 * UNIT, sender=alice)
    assert ygauge.balanceOf(proxy) == 3 * UNIT
    assert rewards.gauge_supply(gauge) == 3 * UNIT
    assert rewards.gauge_balance(gauge, alice) == 3 * UNIT
    assert gauge.totalSupply() == 3 * UNIT
    assert gauge.balanceOf(alice) == 3 * UNIT

def test_deposit_multiple(deployer, alice, bob, proxy, yvault, ygauge, rewards, gauge):
    # deposits from multiple users updates supply and balance as expected
    yvault.mint(alice, UNIT, sender=deployer)
    yvault.approve(gauge, UNIT, sender=alice)
    gauge.deposit(UNIT, sender=alice)
    yvault.mint(bob, 2 * UNIT, sender=deployer)
    yvault.approve(gauge, 2 * UNIT, sender=bob)
    gauge.deposit(2 * UNIT, sender=bob)
    assert ygauge.balanceOf(proxy) == 3 * UNIT
    assert rewards.gauge_supply(gauge) == 3 * UNIT
    assert rewards.gauge_balance(gauge, alice) == UNIT
    assert rewards.gauge_balance(gauge, bob) == 2 * UNIT
    assert gauge.totalSupply() == 3 * UNIT
    assert gauge.balanceOf(alice) == UNIT
    assert gauge.balanceOf(bob) == 2 * UNIT

def test_deposit_excessive(deployer, alice, yvault, gauge):
    # cant deposit more than the balance
    yvault.mint(alice, UNIT, sender=deployer)
    yvault.approve(gauge, UNIT, sender=alice)
    with reverts():
        gauge.deposit(2 * UNIT, sender=alice)

def test_deposit_rewards(deployer, alice, yvault, reward_token, rewards, gauge):
    # depositing reports rewards
    yvault.mint(alice, 3 * UNIT, sender=deployer)
    yvault.approve(gauge, 3 * UNIT, sender=alice)
    gauge.deposit(UNIT, sender=alice)
    reward_token.mint(gauge, 2 * UNIT, sender=deployer)
    assert reward_token.balanceOf(rewards) == 0
    assert rewards.pending(alice) == 0
    gauge.deposit(2 * UNIT, sender=alice)
    assert reward_token.balanceOf(rewards) == 2 * UNIT
    assert rewards.pending(alice) == 2 * UNIT

def test_deposit_rewards_claimable(deployer, alice, bob, yvault, reward_token, rewards, gauge):
    # depositing reports rewards, but only the current user's integral is updated
    yvault.mint(alice, 4 * UNIT, sender=deployer)
    yvault.approve(gauge, 4 * UNIT, sender=alice)
    gauge.deposit(UNIT, sender=alice)
    gauge.deposit(2 * UNIT, bob, sender=alice)
    reward_token.mint(gauge, 6 * UNIT, sender=deployer)
    gauge.deposit(UNIT, sender=alice)
    assert reward_token.balanceOf(rewards) == 6 * UNIT
    assert rewards.pending(alice) == 2 * UNIT
    assert rewards.claimable(gauge, alice) == 0
    assert rewards.pending(bob) == 0
    assert rewards.claimable(gauge, bob) == 4 * UNIT

def test_withdraw(deployer, alice, bob, proxy, yvault, ygauge, rewards, gauge):
    # withdrawing decreases supply and user balance
    yvault.mint(alice, 3 * UNIT, sender=deployer)
    yvault.approve(gauge, 3 * UNIT, sender=alice)
    gauge.deposit(3 * UNIT, sender=alice)
    gauge.withdraw(UNIT, bob, sender=alice)
    assert ygauge.balanceOf(proxy) == 2 * UNIT
    assert yvault.balanceOf(bob) == UNIT
    assert rewards.gauge_supply(gauge) == 2 * UNIT
    assert rewards.gauge_balance(gauge, alice) == 2 * UNIT
    assert gauge.totalSupply() == 2 * UNIT
    assert gauge.balanceOf(alice) == 2 * UNIT

def test_withdraw_excessive(deployer, alice, bob, yvault, gauge):
    # cant withdraw more than balance
    yvault.mint(alice, 3 * UNIT, sender=deployer)
    yvault.approve(gauge, 3 * UNIT, sender=alice)
    gauge.deposit(UNIT, sender=alice)
    gauge.deposit(2 * UNIT, bob, sender=alice)
    with reverts():
        gauge.withdraw(2 * UNIT, sender=alice)

def test_withdraw_from(deployer, alice, bob, proxy, yvault, ygauge, gauge):
    # can withdraw from other users if there's an allowance
    yvault.mint(alice, 4 * UNIT, sender=deployer)
    yvault.approve(gauge, 4 * UNIT, sender=alice)
    gauge.deposit(4 * UNIT, sender=alice)
    gauge.approve(bob, 3 * UNIT, sender=alice)
    gauge.withdraw(UNIT, deployer, alice, sender=bob)
    assert ygauge.balanceOf(proxy) == 3 * UNIT
    assert yvault.balanceOf(deployer) == UNIT
    assert gauge.allowance(alice, bob) == 2 * UNIT
    assert gauge.totalSupply() == 3 * UNIT
    assert gauge.balanceOf(alice) == 3 * UNIT

def test_withdraw_from_excessive(deployer, alice, bob, yvault, gauge):
    # cant withdraw more than allowance from other users
    yvault.mint(alice, 2 * UNIT, sender=deployer)
    yvault.approve(gauge, 2 * UNIT, sender=alice)
    gauge.deposit(2 * UNIT, sender=alice)
    gauge.approve(bob, UNIT, sender=alice)
    with reverts():
        gauge.withdraw(2 * UNIT, deployer, alice, sender=bob)

def test_withdraw_rewards(deployer, alice, bob, yvault, reward_token, rewards, gauge):
    # withdrawing reports rewards
    yvault.mint(alice, UNIT, sender=deployer)
    yvault.approve(gauge, UNIT, sender=alice)
    gauge.deposit(UNIT, sender=alice)
    gauge.approve(bob, UNIT, sender=alice)
    reward_token.mint(gauge, 2 * UNIT, sender=deployer)
    assert reward_token.balanceOf(rewards) == 0
    assert rewards.pending(alice) == 0
    gauge.withdraw(UNIT, deployer, alice, sender=bob)
    assert reward_token.balanceOf(rewards) == 2 * UNIT
    assert rewards.pending(alice) == 2 * UNIT

def test_transfer(deployer, alice, bob, proxy, yvault, ygauge, rewards, gauge):
    # transferring updates balances but not supply
    yvault.mint(alice, 3 * UNIT, sender=deployer)
    yvault.approve(gauge, 3 * UNIT, sender=alice)
    gauge.deposit(3 * UNIT, sender=alice)
    gauge.transfer(bob, UNIT, sender=alice)
    assert ygauge.balanceOf(proxy) == 3 * UNIT
    assert rewards.gauge_supply(gauge) == 3 * UNIT
    assert rewards.gauge_balance(gauge, alice) == 2 * UNIT
    assert rewards.gauge_balance(gauge, bob) == UNIT
    assert gauge.totalSupply() == 3 * UNIT
    assert gauge.balanceOf(alice) == 2 * UNIT
    assert gauge.balanceOf(bob) == UNIT

def test_transfer_excessive(deployer, alice, bob, yvault, gauge):
    # cant transfer more than balance
    yvault.mint(alice, UNIT, sender=deployer)
    yvault.approve(gauge, UNIT, sender=alice)
    gauge.deposit(UNIT, sender=alice)
    with reverts():
        gauge.transfer(bob, 2 * UNIT, sender=alice)

def test_transfer_rewards(deployer, alice, bob, yvault, reward_token, rewards, gauge):
    # transferring doesnt report rewards
    yvault.mint(alice, UNIT, sender=deployer)
    yvault.approve(gauge, UNIT, sender=alice)
    gauge.deposit(UNIT, sender=alice)
    reward_token.mint(gauge, UNIT, sender=deployer)
    gauge.transfer(bob, UNIT, sender=alice)
    assert reward_token.balanceOf(gauge) == UNIT
    assert rewards.pending(alice) == 0
    assert rewards.pending(bob) == 0

def test_transfer_from(deployer, alice, bob, proxy, yvault, ygauge, rewards, gauge):
    # can transfer from other users if there's an allowance
    yvault.mint(alice, 4 * UNIT, sender=deployer)
    yvault.approve(gauge, 4 * UNIT, sender=alice)
    gauge.deposit(4 * UNIT, sender=alice)
    gauge.approve(deployer, 3 * UNIT, sender=alice)
    gauge.transferFrom(alice, bob, UNIT, sender=deployer)
    assert ygauge.balanceOf(proxy) == 4 * UNIT
    assert rewards.gauge_supply(gauge) == 4 * UNIT
    assert rewards.gauge_balance(gauge, alice) == 3 * UNIT
    assert rewards.gauge_balance(gauge, bob) == UNIT
    assert gauge.allowance(alice, deployer) == 2 * UNIT
    assert gauge.totalSupply() == 4 * UNIT
    assert gauge.balanceOf(alice) == 3 * UNIT
    assert gauge.balanceOf(bob) == UNIT

def test_transfer_from_excessive(deployer, alice, bob, yvault, gauge):
    # cant transfer more from other user than the balance
    yvault.mint(alice, UNIT, sender=deployer)
    yvault.approve(gauge, UNIT, sender=alice)
    gauge.deposit(UNIT, sender=alice)
    gauge.approve(bob, 2 * UNIT, sender=alice)
    with reverts():
        gauge.transferFrom(alice, bob, 2 * UNIT, sender=bob)

def test_transfer_from_allowance_excessive(deployer, alice, bob, yvault, gauge):
    # cant transfer more from other user than the allowance
    yvault.mint(alice, 2 * UNIT, sender=deployer)
    yvault.approve(gauge, 2 * UNIT, sender=alice)
    gauge.deposit(2 * UNIT, sender=alice)
    gauge.approve(bob, UNIT, sender=alice)
    with reverts():
        gauge.transferFrom(alice, bob, 2 * UNIT, sender=bob)

def test_approve(alice, bob, gauge):
    # set allowance
    assert gauge.allowance(alice, bob) == 0
    gauge.approve(bob, UNIT, sender=alice)
    assert gauge.allowance(alice, bob) == UNIT

def test_lower_decimals(accounts, project, deployer, proxy, reward_token, registry, rewards):
    # should be able to deposit vaults with lower number of decimals
    asset = Contract('0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48')
    whale = accounts['0xD6153F5af5679a75cC85D8974463545181f48772']
    deployer.transfer(whale, UNIT)
    yvault = Contract('0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204')
    ygauge = Contract('0x622fA41799406B120f9a40dA843D358b7b2CFEE3')

    gauge = project.Gauge.deploy(ygauge, proxy, reward_token, rewards, sender=deployer)
    registry.set_gauge_map(ygauge, gauge, sender=deployer)
    data = ygauge.approve.encode_input(gauge, MAX_VALUE)
    proxy.call(ygauge, data, sender=deployer)

    amt = 1000 * 10**6
    asset.approve(yvault, amt, sender=whale)
    yvault.deposit(amt, whale, sender=whale)
    yv_amt = yvault.balanceOf(whale)
    yvault.approve(gauge, yv_amt, sender=whale)
    gauge.deposit(yv_amt, sender=whale)
    assert yvault.balanceOf(whale) == 0
    assert gauge.balanceOf(whale) == yv_amt
    assert rewards.gauge_balance(gauge, whale) == yv_amt * 10**12
    gauge.withdraw(yv_amt, sender=whale)
    assert yvault.balanceOf(whale) == yv_amt
    assert gauge.balanceOf(whale) == 0
    assert rewards.gauge_balance(gauge, whale) == 0
