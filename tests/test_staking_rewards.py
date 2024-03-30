from ape import reverts
from pytest import fixture
from _constants import *

HARVEST_FEE_IDX        = 0 # harvest
DT_FEE_IDX             = 1 # claim discount token without redeem
DT_REDEEM_SELL_FEE_IDX = 2 # claim with redeem, without ETH
DT_REDEEM_FEE_IDX      = 3 # claim with redeem, with ETH
LT_FEE_IDX             = 4 # claim locking token without deposit into ll
LT_DEPOSIT_FEE_IDX     = 5 # claim locking token with deposit into ll

MASK = 2**128 - 1
SMALL_MASK = 2**32 - 1
BIG_MASK = 2**112 - 1

@fixture
def locking_token(project, deployer):
    return project.MockToken.deploy(sender=deployer)

@fixture
def discount_token(project, deployer):
    return project.MockToken.deploy(sender=deployer)

@fixture
def staking(project, deployer):
    return project.MockStaking.deploy(sender=deployer)

@fixture
def rewards(project, deployer, proxy, locking_token, discount_token, staking):
    rewards = project.StakingRewards.deploy(proxy, staking, locking_token, discount_token, sender=deployer)
    data = locking_token.approve.encode_input(rewards, MAX_VALUE)
    proxy.call(locking_token, data, sender=deployer)
    proxy.call(discount_token, data, sender=deployer)
    staking.set_rewards(rewards, sender=deployer)
    return rewards

@fixture
def redeem_token(project, deployer):
    return project.MockToken.deploy(sender=deployer)

@fixture
def redeemer(project, deployer, locking_token, discount_token, rewards, redeem_token):
    redeemer = project.MockStakingRedeemer.deploy(locking_token, discount_token, redeem_token, sender=deployer)
    rewards.set_redeemer(redeemer, sender=deployer)
    return redeemer

def test_report(chain, deployer, alice, locking_token, discount_token, proxy, staking, rewards):
    # reporting a user's balance causes their rewards to be synced
    staking.mint(alice, 2 * UNIT, sender=deployer)
    locking_token.mint(proxy, 4 * UNIT, sender=deployer)
    discount_token.mint(proxy, 6 * UNIT, sender=deployer)
    assert rewards.packed_next() == 0
    rewards.harvest(4 * UNIT, 6 * UNIT, sender=deployer)
    assert rewards.pending(alice) == (0, 0)
    assert rewards.claimable(alice) == (0, 0)

    chain.pending_timestamp += 2 * WEEK
    chain.mine()
    assert rewards.packed_account_integrals(alice) == 0
    assert rewards.pending(alice) == (0, 0)
    assert rewards.claimable(alice) == (4 * UNIT, 6 * UNIT)
    staking.burn(alice, UNIT, sender=deployer)
    packed = rewards.packed_integrals()
    assert packed > 0
    assert rewards.packed_account_integrals(alice) == packed
    assert rewards.pending(alice) == (4 * UNIT, 6 * UNIT)
    assert rewards.claimable(alice) == (4 * UNIT, 6 * UNIT)
 
def test_report_deposit(chain, deployer, alice, bob, locking_token, discount_token, proxy, staking, rewards):
    # rewards harvested before depositing arent distributed to that user
    staking.mint(alice, 2 * UNIT, sender=deployer)
    locking_token.mint(proxy, 4 * UNIT, sender=deployer)
    discount_token.mint(proxy, 6 * UNIT, sender=deployer)
    rewards.harvest(4 * UNIT, 6 * UNIT, sender=deployer)
    chain.pending_timestamp += 2 * WEEK
    staking.mint(bob, UNIT, sender=deployer)
    packed = rewards.packed_integrals()
    assert packed > 0
    assert rewards.packed_account_integrals(bob) == packed
    assert rewards.pending(bob) == (0, 0)
    assert rewards.claimable(bob) == (0, 0)

def test_report_permission(deployer, alice, rewards):
    # only the staking contract can report
    staking2 = project.MockStaking.deploy(sender=deployer)
    staking2.set_rewards(rewards, sender=deployer)
    with reverts():
        staking2.mint(alice, UNIT, sender=deployer)

def test_harvest(chain, deployer, alice, locking_token, discount_token, proxy, staking, rewards):
    # harvesting transfers tokens from the proxy and updates 'next' rewards
    staking.mint(alice, 2 * UNIT, sender=deployer)
    locking_token.mint(proxy, 4 * UNIT, sender=deployer)
    discount_token.mint(proxy, 8 * UNIT, sender=deployer)
    assert locking_token.balanceOf(proxy) == 4 * UNIT
    assert locking_token.balanceOf(rewards) == 0
    assert discount_token.balanceOf(proxy) == 8 * UNIT
    assert discount_token.balanceOf(rewards) == 0
    ts = chain.pending_timestamp
    rewards.harvest(4 * UNIT, 8 * UNIT, sender=deployer)
    assert locking_token.balanceOf(proxy) == 0
    assert locking_token.balanceOf(rewards) == 4 * UNIT
    assert discount_token.balanceOf(proxy) == 0
    assert discount_token.balanceOf(rewards) == 8 * UNIT
    streaming = rewards.packed_streaming()
    assert streaming >> 224 == ts
    assert streaming & (2**224 - 1) == 0
    next = rewards.packed_next()
    assert next & MASK == 4 * UNIT
    assert next >> 128 == 8 * UNIT
    assert rewards.packed_integrals() == 0

def test_harvest_multiple(chain, deployer, alice, locking_token, discount_token, proxy, staking, rewards):
    # harvesting multiple times in the same week adds to the 'next' rewards
    staking.mint(alice, 2 * UNIT, sender=deployer)
    locking_token.mint(proxy, UNIT, sender=deployer)
    discount_token.mint(proxy, 2 * UNIT, sender=deployer)
    rewards.harvest(UNIT, 2 * UNIT, sender=deployer)
    locking_token.mint(proxy, 3 * UNIT, sender=deployer)
    discount_token.mint(proxy, 4 * UNIT, sender=deployer)
    ts = chain.pending_timestamp
    rewards.harvest(3 * UNIT, 4 * UNIT, sender=deployer)
    assert locking_token.balanceOf(rewards) == 4 * UNIT
    assert discount_token.balanceOf(rewards) == 6 * UNIT
    streaming = rewards.packed_streaming()
    assert streaming >> 224 == ts
    assert streaming & (2**224 - 1) == 0
    next = rewards.packed_next()
    assert next & MASK == 4 * UNIT
    assert next >> 128 == 6 * UNIT
    assert rewards.packed_integrals() == 0

def test_harvest_multiple_stream(chain, deployer, alice, locking_token, discount_token, proxy, staking, rewards):
    # harvesting multiple times in consecutive weeks updates integrals
    staking.mint(alice, 2 * UNIT, sender=deployer)
    locking_token.mint(proxy, 4 * UNIT, sender=deployer)
    discount_token.mint(proxy, 8 * UNIT, sender=deployer)
    week = chain.pending_timestamp // WEEK
    rewards.harvest(4 * UNIT, 8 * UNIT, sender=deployer)
    locking_token.mint(proxy, 2 * UNIT, sender=deployer)
    discount_token.mint(proxy, 4 * UNIT, sender=deployer)
    ts = (week + 1) * WEEK + WEEK // 4
    chain.pending_timestamp = ts
    rewards.harvest(2 * UNIT, 4 * UNIT, sender=deployer)
    streaming = rewards.packed_streaming()
    assert streaming >> 224 == ts
    assert (streaming >> 112) & BIG_MASK == 3 * UNIT
    assert streaming & BIG_MASK == 6 * UNIT
    next = rewards.packed_next()
    assert next & MASK == 2 * UNIT
    assert next >> 128 == 4 * UNIT
    integrals = rewards.packed_integrals()
    assert integrals & MASK == UNIT // 2
    assert integrals >> 128 == UNIT
    assert rewards.claimable(alice) == (UNIT, 2 * UNIT)
    chain.pending_timestamp = ts + WEEK // 2
    with chain.isolate():
        chain.mine()
        assert rewards.claimable(alice) == (3 * UNIT, 6 * UNIT)
    rewards.sync(sender=deployer)
    integrals = rewards.packed_integrals()
    assert integrals & MASK == UNIT * 3 // 2
    assert integrals >> 128 == UNIT * 3
    assert rewards.claimable(alice) == (3 * UNIT, 6 * UNIT)

def test_harvest_excessive(deployer, alice, locking_token, discount_token, proxy, staking, rewards):
    # cant harvest more than balance
    staking.mint(alice, UNIT, sender=deployer)
    locking_token.mint(proxy, UNIT, sender=deployer)
    discount_token.mint(proxy, UNIT, sender=deployer)
    with reverts():
        rewards.harvest(2 * UNIT, UNIT, sender=deployer)
    with reverts():
        rewards.harvest(UNIT, 2 * UNIT, sender=deployer)
    rewards.harvest(UNIT, UNIT, sender=deployer)

def test_harvest_no_supply(deployer, locking_token, discount_token, proxy, rewards):
    # cant harvest if there's nothing staked
    locking_token.mint(proxy, UNIT, sender=deployer)
    discount_token.mint(proxy, UNIT, sender=deployer)
    with reverts():
        rewards.harvest(UNIT, UNIT, sender=deployer)

def test_harvest_fee(deployer, alice, bob, locking_token, discount_token, proxy, staking, rewards):
    # fees are transfered to the harvester
    rewards.set_fee_rate(HARVEST_FEE_IDX, 2_500, sender=deployer)
    staking.mint(alice, UNIT, sender=deployer)
    locking_token.mint(proxy, 4 * UNIT, sender=deployer)
    discount_token.mint(proxy, 8 * UNIT, sender=deployer)
    rewards.harvest(4 * UNIT, 8 * UNIT, bob, sender=alice)
    assert locking_token.balanceOf(rewards) == 3 * UNIT
    assert locking_token.balanceOf(bob) == UNIT
    assert discount_token.balanceOf(rewards) == 6 * UNIT
    assert discount_token.balanceOf(bob) == 2 * UNIT
    next = rewards.packed_next()
    assert next & MASK == 3 * UNIT
    assert next >> 128 == 6 * UNIT

def test_claim_naked(chain, deployer, alice, bob, locking_token, discount_token, proxy, staking, rewards):
    # claim naked reward tokens
    staking.mint(alice, 2 * UNIT, sender=deployer)
    locking_token.mint(proxy, 4 * UNIT, sender=deployer)
    discount_token.mint(proxy, 6 * UNIT, sender=deployer)
    rewards.harvest(4 * UNIT, 6 * UNIT, sender=deployer)
    chain.pending_timestamp += 2 * WEEK
    staking.burn(alice, 2 * UNIT, sender=deployer)
    assert rewards.pending(alice) == (4 * UNIT, 6 * UNIT)
    assert rewards.claimable(alice) == (4 * UNIT, 6 * UNIT)
    assert rewards.claim(bob, b"", sender=alice).return_value == (4 * UNIT, 6 * UNIT)
    assert rewards.pending(alice) == (0, 0)
    assert rewards.claimable(alice) == (0, 0)
    assert locking_token.balanceOf(bob) == 4 * UNIT
    assert discount_token.balanceOf(bob) == 6 * UNIT

def test_claim_naked_fee(chain, deployer, alice, bob, locking_token, discount_token, proxy, staking, rewards):
    # claim naked reward tokens, with fee
    staking.mint(alice, 2 * UNIT, sender=deployer)
    locking_token.mint(proxy, 4 * UNIT, sender=deployer)
    discount_token.mint(proxy, 5 * UNIT, sender=deployer)
    rewards.harvest(4 * UNIT, 5 * UNIT, sender=deployer)
    rewards.set_fee_rate(LT_FEE_IDX, 2_500, sender=deployer)
    rewards.set_fee_rate(DT_FEE_IDX, 2_000, sender=deployer)
    chain.pending_timestamp += 2 * WEEK
    staking.burn(alice, 2 * UNIT, sender=deployer)
    assert rewards.claim(bob, b"", sender=alice).return_value == (3 * UNIT, 4 * UNIT)
    assert locking_token.balanceOf(bob) == 3 * UNIT
    assert discount_token.balanceOf(bob) == 4 * UNIT
    assert rewards.pending_fees() == (UNIT, UNIT)

def test_claim_redeem_sell(chain, deployer, alice, bob, locking_token, discount_token, proxy, staking, rewards, redeemer, redeem_token):
    # claim with redeem, without ETH
    staking.mint(alice, 2 * UNIT, sender=deployer)
    locking_token.mint(proxy, 4 * UNIT, sender=deployer)
    discount_token.mint(proxy, 6 * UNIT, sender=deployer)
    rewards.harvest(4 * UNIT, 6 * UNIT, sender=deployer)
    chain.pending_timestamp += 2 * WEEK
    staking.burn(alice, 2 * UNIT, sender=deployer)
    assert rewards.claim(bob, b"dcba", sender=alice).return_value == (24 * UNIT, 0)
    assert locking_token.balanceOf(redeemer) == 4 * UNIT
    assert discount_token.balanceOf(redeemer) == 6 * UNIT
    assert redeem_token.balanceOf(bob) == 24 * UNIT

def test_claim_redeem_sell_fee(chain, deployer, alice, bob, locking_token, discount_token, proxy, staking, rewards, redeemer, redeem_token):
    # claim with redeem, without ETH, with fee
    staking.mint(alice, 2 * UNIT, sender=deployer)
    locking_token.mint(proxy, 4 * UNIT, sender=deployer)
    discount_token.mint(proxy, 6 * UNIT, sender=deployer)
    rewards.harvest(4 * UNIT, 6 * UNIT, sender=deployer)
    rewards.set_fee_rate(LT_FEE_IDX, 10_000, sender=deployer)
    rewards.set_fee_rate(LT_DEPOSIT_FEE_IDX, 2_500, sender=deployer)
    rewards.set_fee_rate(DT_FEE_IDX, 10_000, sender=deployer)
    rewards.set_fee_rate(DT_REDEEM_SELL_FEE_IDX, 5_000, sender=deployer)
    chain.pending_timestamp += 2 * WEEK
    staking.burn(alice, 2 * UNIT, sender=deployer)
    assert rewards.claim(bob, b"dcba", sender=alice).return_value == (15 * UNIT, 0)
    assert locking_token.balanceOf(redeemer) == 3 * UNIT
    assert discount_token.balanceOf(redeemer) == 3 * UNIT
    assert redeem_token.balanceOf(bob) == 15 * UNIT
    assert rewards.pending_fees() == (UNIT, 3 * UNIT)

def test_claim_redeem_eth(chain, deployer, alice, bob, locking_token, discount_token, proxy, staking, rewards, redeemer, redeem_token):
    # claim with redeem, with ETH
    staking.mint(alice, 2 * UNIT, sender=deployer)
    locking_token.mint(proxy, 4 * UNIT, sender=deployer)
    discount_token.mint(proxy, 6 * UNIT, sender=deployer)
    rewards.harvest(4 * UNIT, 6 * UNIT, sender=deployer)
    chain.pending_timestamp += 2 * WEEK
    staking.burn(alice, 2 * UNIT, sender=deployer)
    assert rewards.claim(bob, b"dcba", value=UNIT, sender=alice).return_value == (25 * UNIT, 0)
    assert locking_token.balanceOf(redeemer) == 4 * UNIT
    assert discount_token.balanceOf(redeemer) == 6 * UNIT
    assert redeem_token.balanceOf(bob) == 25 * UNIT
    assert redeemer.balance == UNIT

def test_claim_redeem_eth_fee(chain, deployer, alice, bob, locking_token, discount_token, proxy, staking, rewards, redeemer, redeem_token):
    # claim with redeem, with ETH, with fee
    staking.mint(alice, 2 * UNIT, sender=deployer)
    locking_token.mint(proxy, 4 * UNIT, sender=deployer)
    discount_token.mint(proxy, 6 * UNIT, sender=deployer)
    rewards.harvest(4 * UNIT, 6 * UNIT, sender=deployer)
    rewards.set_fee_rate(LT_FEE_IDX, 10_000, sender=deployer)
    rewards.set_fee_rate(LT_DEPOSIT_FEE_IDX, 2_500, sender=deployer)
    rewards.set_fee_rate(DT_FEE_IDX, 10_000, sender=deployer)
    rewards.set_fee_rate(DT_REDEEM_SELL_FEE_IDX, 10_000, sender=deployer)
    rewards.set_fee_rate(DT_REDEEM_FEE_IDX, 5_000, sender=deployer)
    chain.pending_timestamp += 2 * WEEK
    staking.burn(alice, 2 * UNIT, sender=deployer)
    assert rewards.claim(bob, b"dcba", value=UNIT, sender=alice).return_value == (16 * UNIT, 0)
    assert locking_token.balanceOf(redeemer) == 3 * UNIT
    assert discount_token.balanceOf(redeemer) == 3 * UNIT
    assert redeem_token.balanceOf(bob) == 16 * UNIT
    assert rewards.pending_fees() == (UNIT, 3 * UNIT)
    assert redeemer.balance == UNIT

def test_claim_redeem_no_redemeer(deployer, alice, bob, locking_token, discount_token, proxy, staking, rewards):
    # cant redeem without a redeemer set
    rewards.set_redeemer(ZERO_ADDRESS, sender=deployer)
    staking.mint(alice, 2 * UNIT, sender=deployer)
    locking_token.mint(proxy, 4 * UNIT, sender=deployer)
    discount_token.mint(proxy, 6 * UNIT, sender=deployer)
    rewards.harvest(4 * UNIT, 6 * UNIT, sender=deployer)
    with reverts():
        rewards.claim(bob, b"dcba", sender=alice)

def test_claim_stream(chain, deployer, alice, bob, locking_token, discount_token, proxy, staking, rewards):
    # claim reward tokens from stream
    staking.mint(alice, 2 * UNIT, sender=deployer)
    locking_token.mint(proxy, 3 * UNIT, sender=deployer)
    discount_token.mint(proxy, 6 * UNIT, sender=deployer)
    week = chain.pending_timestamp // WEEK
    rewards.harvest(3 * UNIT, 6 * UNIT, sender=deployer)
    chain.pending_timestamp = (week + 1) * WEEK + WEEK // 3
    with chain.isolate():
        chain.mine()
        assert rewards.claimable(alice) == (UNIT, 2 * UNIT)
    assert rewards.claim(bob, b"", sender=alice).return_value == (UNIT, 2 * UNIT)
    assert rewards.pending(alice) == (0, 0)
    assert rewards.claimable(alice) == (0, 0)
    assert locking_token.balanceOf(bob) == UNIT
    assert discount_token.balanceOf(bob) == 2 * UNIT

def test_claim_stream_multiple(chain, deployer, alice, bob, locking_token, discount_token, proxy, staking, rewards):
    # claim reward tokens from stream multiple times
    staking.mint(alice, 2 * UNIT, sender=deployer)
    locking_token.mint(proxy, 4 * UNIT, sender=deployer)
    discount_token.mint(proxy, 8 * UNIT, sender=deployer)
    week = chain.pending_timestamp // WEEK
    rewards.harvest(4 * UNIT, 8 * UNIT, sender=deployer)
    ts = (week + 1) * WEEK + WEEK // 4
    chain.pending_timestamp = ts
    assert rewards.claim(bob, b"", sender=alice).return_value == (UNIT, 2 * UNIT)

    chain.pending_timestamp = ts + WEEK // 2
    with chain.isolate():
        chain.mine()
        assert rewards.claimable(alice) == (2 * UNIT, 4 * UNIT)
    staking.burn(alice, 2 * UNIT, sender=deployer)
    assert rewards.pending(alice) == (2 * UNIT, 4 * UNIT)
    assert rewards.claimable(alice) == (2 * UNIT, 4 * UNIT)
    assert rewards.claim(bob, b"", sender=alice).return_value == (2 * UNIT, 4 * UNIT)

def test_set_fee_rate(deployer, rewards):
    # fees can be individually set
    for i in range(6):
        assert rewards.fee_rates(i) == 0
        rewards.set_fee_rate(i, 1_000 * i, sender=deployer)

    for i in range(6):
        assert rewards.fee_rates(i) == 1_000 * i

def test_set_fee_rate_max(deployer, rewards):
    # cant set fee of more than 100%
    with reverts():
        rewards.set_fee_rate(0, 10_001, sender=deployer)

def test_set_fee_rate_invalid_index(deployer, rewards):
    # cant set fee for invalid index
    with reverts():
        rewards.set_fee_rate(6, 1_000, sender=deployer)

def test_set_fee_rate_permission(alice, rewards):
    # only management can set a fee rate
    with reverts():
        rewards.set_fee_rate(0, 1_000, sender=alice)

def test_claim_fees(chain, deployer, alice, bob, proxy, locking_token, discount_token, staking, rewards):
    # claimed fees are sent to treasury
    rewards.set_treasury(bob, sender=deployer)
    rewards.set_fee_rate(LT_FEE_IDX, 2_500, sender=deployer)
    rewards.set_fee_rate(DT_FEE_IDX, 5_000, sender=deployer)
    staking.mint(alice, UNIT, sender=deployer)

    locking_token.mint(proxy, 4 * UNIT, sender=deployer)
    discount_token.mint(proxy, 6 * UNIT, sender=deployer)
    rewards.harvest(4 * UNIT, 6 * UNIT, sender=deployer)
    chain.pending_timestamp += 2 * WEEK
    rewards.claim(sender=alice)
    assert rewards.pending_fees() == (UNIT, 3 * UNIT)
    rewards.claim_fees(sender=alice)
    assert rewards.pending_fees() == (0, 0)
    assert locking_token.balanceOf(bob) == UNIT
    assert discount_token.balanceOf(bob) == 3 * UNIT

def test_set_redeemer(project, deployer, locking_token, discount_token, rewards, redeem_token, redeemer):
    # setting new redeemer retracts previous allowance and sets a new one
    redeemer2 = project.MockStakingRedeemer.deploy(locking_token, discount_token, redeem_token, sender=deployer)
    assert rewards.redeemer() == redeemer
    assert locking_token.allowance(rewards, redeemer) == MAX_VALUE
    assert locking_token.allowance(rewards, redeemer2) == 0
    assert discount_token.allowance(rewards, redeemer) == MAX_VALUE
    assert discount_token.allowance(rewards, redeemer2) == 0
    rewards.set_redeemer(redeemer2, sender=deployer)
    assert locking_token.allowance(rewards, redeemer) == 0
    assert locking_token.allowance(rewards, redeemer2) == MAX_VALUE
    assert discount_token.allowance(rewards, redeemer) == 0
    assert discount_token.allowance(rewards, redeemer2) == MAX_VALUE

def test_set_no_redeemer(deployer, locking_token, discount_token, rewards, redeemer):
    # redeemer can be cleared, effectively disabling redemptions
    assert rewards.redeemer() == redeemer
    assert locking_token.allowance(rewards, redeemer) == MAX_VALUE
    assert discount_token.allowance(rewards, redeemer) == MAX_VALUE
    rewards.set_redeemer(ZERO_ADDRESS, sender=deployer)
    assert locking_token.allowance(rewards, redeemer) == 0
    assert discount_token.allowance(rewards, redeemer) == 0

def test_set_redeemer_permission(project, deployer, alice, locking_token, discount_token, rewards, redeem_token):
    # only management can set a new redeemer
    redeemer2 = project.MockStakingRedeemer.deploy(locking_token, discount_token, redeem_token, sender=deployer)
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
