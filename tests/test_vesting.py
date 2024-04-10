from ape import reverts
from ape import Contract
from pytest import fixture
from _constants import *

MESSAGE = '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'

@fixture
def staking_and_rewards(project, deployer, proxy, liquid_locker, locking_token, discount_token):
    staking = project.Staking.deploy(liquid_locker, sender=deployer)
    rewards = project.StakingRewards.deploy(proxy, staking, locking_token, discount_token, sender=deployer)
    staking.set_rewards(rewards, sender=deployer)
    data = locking_token.approve.encode_input(rewards, MAX_VALUE)
    proxy.call(locking_token, data, sender=deployer)
    return staking, rewards

@fixture
def staking(staking_and_rewards):
    return staking_and_rewards[0]

@fixture
def rewards(staking_and_rewards):
    return staking_and_rewards[1]

@fixture
def vesting_impl(project, deployer):
    return project.VestingEscrowLL.deploy(sender=deployer)

@fixture
def factory(project, alice, deployer, locking_token, vesting_impl):
    return project.VestingEscrowFactory.deploy(vesting_impl, locking_token, deployer, sender=alice)

@fixture
def depositor(project, deployer, locking_token, liquid_locker, staking):
    return project.VestingEscrowDepositor.deploy(locking_token, liquid_locker, staking, deployer, sender=deployer)

@fixture
def delegate_registry():
    return Contract('0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446')

@fixture
def delegation_space():
    return bytes('1uptokyo.eth', 'utf-8')

@fixture
def operator(project, deployer, staking, rewards, delegate_registry, delegation_space):
    return project.VestingOperator.deploy(staking, rewards, delegate_registry, delegation_space, sender=deployer)

def test_create_vest(chain, ychad, alice, locking_token, factory):
    # anyone can create a yfi vest
    locking_token.approve(factory, 10 * UNIT, sender=ychad)
    assert factory.num_vests() == 0
    assert factory.pending_vests(0).amount == 0
    assert locking_token.balanceOf(factory) == 0
    ts = chain.pending_timestamp + 1
    assert factory.create_vest(alice, 10 * UNIT, 5 * DAY, ts, DAY, sender=ychad).return_value == 0
    assert factory.num_vests() == 1
    vest = factory.pending_vests(0)
    assert vest.recipient == alice
    assert vest.amount == 10 * UNIT
    assert vest.duration == 5 * DAY
    assert vest.start == ts
    assert vest.cliff == DAY
    assert locking_token.balanceOf(factory) == 10 * UNIT

def test_create_vest_multiple(ychad, alice, locking_token, factory):
    # vests are stored separately
    locking_token.approve(factory, 10 * UNIT, sender=ychad)
    assert factory.create_vest(alice, 4 * UNIT, 5 * DAY, sender=ychad).return_value == 0
    assert factory.create_vest(alice, 6 * UNIT, 5 * DAY, sender=ychad).return_value == 1
    assert factory.pending_vests(0).amount == 4 * UNIT
    assert factory.pending_vests(1).amount == 6 * UNIT

def test_deploy_vesting_contract(chain, ychad, deployer, alice, locking_token, voting_escrow, proxy, staking, factory, depositor):
    # users with a vest can pick a liquid locker and deploy a vesting contract
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    ts = chain.pending_timestamp
    factory.create_vest(alice, 3 * UNIT, 5 * DAY, ts, DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    vesting_contract, amount = factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice).return_value
    assert factory.pending_vests(0).amount == 2 * UNIT
    vesting_contract = project.VestingEscrowLL.at(vesting_contract)
    assert amount == SCALE
    assert staking.balanceOf(vesting_contract) == SCALE
    assert vesting_contract.factory() == factory
    assert vesting_contract.recipient() == alice
    assert vesting_contract.token() == staking
    assert vesting_contract.start_time() == ts
    assert vesting_contract.end_time() == ts + 5 * DAY
    assert vesting_contract.cliff_length() == DAY
    assert vesting_contract.total_locked() == SCALE
    assert not vesting_contract.open_claim()
    assert vesting_contract.owner() == deployer
    assert voting_escrow.locked(proxy).amount == UNIT

def test_deploy_vesting_contract_excessive(ychad, deployer, alice, bob, locking_token, staking, factory, depositor):
    # cannot deposit more than vest size
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    factory.create_vest(alice, UNIT, 5 * DAY, sender=ychad)
    factory.create_vest(bob, 2 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    with reverts():
        factory.deploy_vesting_contract(0, staking, 2 * UNIT, sender=alice)

def test_deploy_vesting_contract_permission(ychad, deployer, alice, bob, locking_token, staking, factory, depositor):
    # cannot deploy vesting contract for another user's vest
    locking_token.approve(factory, UNIT, sender=ychad)
    factory.create_vest(alice, UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    with reverts():
        factory.deploy_vesting_contract(0, staking, UNIT, sender=bob)

def test_deploy_vesting_contract_invalid(ychad, alice, locking_token, staking, factory):
    # cannot deploy vesting contract for liquid locker without approval
    locking_token.approve(factory, UNIT, sender=ychad)
    factory.create_vest(alice, UNIT, 5 * DAY, sender=ychad)
    with reverts():
        factory.deploy_vesting_contract(0, staking, UNIT, sender=alice)

def test_revoke_full_vest(ychad, deployer, alice, bob, locking_token, factory):
    # yfi can be clawed back
    locking_token.approve(factory, 4 * UNIT, sender=ychad)
    factory.create_vest(alice, 4 * UNIT, 5 * DAY, sender=ychad)
    factory.revoke(0, bob, sender=deployer)
    assert factory.pending_vests(0).amount == 0
    assert locking_token.balanceOf(bob) == 4 * UNIT

def test_revoke_pending_vest(ychad, deployer, alice, bob, locking_token, staking, factory, depositor):
    # remaining yfi that is not deposited into a liquid locker yet can be clawed back
    locking_token.approve(factory, 10 * UNIT, sender=ychad)
    factory.create_vest(alice, 4 * UNIT, 5 * DAY, sender=ychad)
    factory.create_vest(bob, 6 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice)
    factory.revoke(0, sender=deployer)
    assert factory.pending_vests(0).amount == 0
    assert factory.pending_vests(1).amount == 6 * UNIT
    assert locking_token.balanceOf(factory) == 6 * UNIT
    assert locking_token.balanceOf(deployer) == 3 * UNIT

def test_revoke_vest_permission(ychad, alice, locking_token, factory):
    # only factory owner can claw back
    locking_token.approve(factory, 4 * UNIT, sender=ychad)
    factory.create_vest(alice, 4 * UNIT, 5 * DAY, sender=ychad)
    with reverts():
        factory.revoke(0, sender=alice)

def test_set_liquid_locker(deployer, factory):
    # liquid lockers can be approved by setting a deposit contract
    ll = '0x1111111111111111111111111111111111111111'
    depositor = '0x2222222222222222222222222222222222222222'
    assert factory.liquid_lockers(ll) == ZERO_ADDRESS
    factory.set_liquid_locker(ll, depositor, sender=deployer)
    assert factory.liquid_lockers(ll) == depositor

def test_set_liquid_locker_permission(alice, factory):
    # only owner can set liquid lockers
    ll = '0x1111111111111111111111111111111111111111'
    depositor = '0x2222222222222222222222222222222222222222'
    with reverts():
        factory.set_liquid_locker(ll, depositor, sender=alice)

def test_set_operator(deployer, staking, factory, operator):
    # owner can approve operators
    assert not factory.operators(staking, operator)
    factory.set_operator(staking, operator, True, sender=deployer)
    assert factory.operators(staking, operator)

def test_set_operator_permission(alice, staking, factory, operator):
    # only owner can approve operators
    with reverts():
        factory.set_operator(staking, operator, True, sender=alice)

def test_revoke_approve_operator(deployer, staking, factory, operator):
    # owner can revoke approval
    factory.set_operator(staking, operator, True, sender=deployer)
    assert factory.operators(staking, operator)
    factory.set_operator(staking, operator, False, sender=deployer)
    assert not factory.operators(staking, operator)

def test_add_operator(ychad, deployer, alice, locking_token, staking, factory, depositor, operator):
    # approved operators can be added to a vesting contract
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    factory.create_vest(alice, 3 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    vesting, _ = factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice).return_value
    vesting = project.VestingEscrowLL.at(vesting)
    factory.set_operator(staking, operator, True, sender=deployer)
    assert not vesting.operators(operator)
    vesting.set_operator(operator, True, sender=alice)
    assert vesting.operators(operator)

def test_add_operator_invalid(ychad, deployer, alice, locking_token, staking, factory, depositor, operator):
    # cant add operators without prior approval
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    factory.create_vest(alice, 3 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    vesting, _ = factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice).return_value
    vesting = project.VestingEscrowLL.at(vesting)
    with reverts():
        vesting.set_operator(operator, True, sender=alice)

def test_add_operator_permission(ychad, deployer, alice, locking_token, staking, factory, depositor, operator):
    # only recipient can add operators
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    factory.create_vest(alice, 3 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    vesting, _ = factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice).return_value
    vesting = project.VestingEscrowLL.at(vesting)
    factory.set_operator(staking, operator, True, sender=deployer)
    with reverts():
        vesting.set_operator(operator, True, sender=deployer)

def test_remove_operator(ychad, deployer, alice, locking_token, staking, factory, depositor, operator):
    # recipient can remove operators again
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    factory.create_vest(alice, 3 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    vesting, _ = factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice).return_value
    vesting = project.VestingEscrowLL.at(vesting)
    factory.set_operator(staking, operator, True, sender=deployer)
    vesting.set_operator(operator, True, sender=alice)
    assert vesting.operators(operator)
    vesting.set_operator(operator, False, sender=alice)
    assert not vesting.operators(operator)

def test_call(ychad, deployer, alice, bob, locking_token, staking, factory, depositor):
    # operators can call through the vesting contract
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    factory.create_vest(alice, 3 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    vesting, _ = factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice).return_value
    vesting = project.VestingEscrowLL.at(vesting)
    factory.set_operator(staking, bob, True, sender=deployer)
    vesting.set_operator(bob, True, sender=alice)
    token = project.MockToken.deploy(sender=deployer)
    token.mint(vesting, UNIT, sender=deployer)
    data = token.transfer.encode_input(alice, UNIT)
    vesting.call(token, data, sender=bob)
    assert token.balanceOf(alice) == UNIT

def test_call_permission(ychad, deployer, alice, bob, locking_token, staking, factory, depositor):
    # only operators can call through the vesting contract
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    factory.create_vest(alice, 3 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    vesting, _ = factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice).return_value
    vesting = project.VestingEscrowLL.at(vesting)
    token = project.MockToken.deploy(sender=deployer)
    token.mint(vesting, UNIT, sender=deployer)
    data = token.transfer.encode_input(alice, UNIT)
    with reverts():
        vesting.call(token, data, sender=bob)

def test_call_recipient(ychad, deployer, alice, locking_token, staking, factory, depositor):
    # recipient can call through the vesting contract
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    factory.create_vest(alice, 3 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    vesting, _ = factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice).return_value
    vesting = project.VestingEscrowLL.at(vesting)
    token = project.MockToken.deploy(sender=deployer)
    token.mint(vesting, UNIT, sender=deployer)
    data = token.transfer.encode_input(alice, UNIT)
    vesting.call(token, data, sender=alice)
    assert token.balanceOf(alice) == UNIT

def test_call_recipient_token(ychad, deployer, alice, locking_token, staking, factory, depositor):
    # recipient cant call functions on the vesting token
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    factory.create_vest(alice, 3 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    vesting, _ = factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice).return_value
    vesting = project.VestingEscrowLL.at(vesting)
    data = staking.transfer.encode_input(alice, UNIT)
    with reverts():
        vesting.call(staking, data, sender=alice)

def test_sign(ychad, deployer, alice, locking_token, staking, factory, depositor):
    # recipient can sign messages
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    factory.create_vest(alice, 3 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    vesting, _ = factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice).return_value
    vesting = project.VestingEscrowLL.at(vesting)
    with reverts():
        vesting.isValidSignature(MESSAGE, b'')
    vesting.set_signed_message(MESSAGE, True, sender=alice)
    assert vesting.isValidSignature(MESSAGE, b'').hex() == '0x1626ba7e'

def test_sign_permission(ychad, deployer, alice, locking_token, staking, factory, depositor):
    # only recipient can sign messages
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    factory.create_vest(alice, 3 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    vesting, _ = factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice).return_value
    vesting = project.VestingEscrowLL.at(vesting)
    with reverts():
        vesting.set_signed_message(MESSAGE, True, sender=deployer)

def test_unsign(ychad, deployer, alice, locking_token, staking, factory, depositor):
    # recipient can unsign messages
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    factory.create_vest(alice, 3 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    vesting, _ = factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice).return_value
    vesting = project.VestingEscrowLL.at(vesting)
    vesting.set_signed_message(MESSAGE, True, sender=alice)
    assert vesting.isValidSignature(MESSAGE, b'').hex() == '0x1626ba7e'
    vesting.set_signed_message(MESSAGE, False, sender=alice)
    with reverts():
        vesting.isValidSignature(MESSAGE, b'')
    
def test_set_snapshot_delegate(ychad, deployer, alice, bob, locking_token, staking, factory, depositor, operator, delegate_registry, delegation_space):
    # snapshot voting weight can be delegated
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    factory.create_vest(alice, 3 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    vesting, _ = factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice).return_value
    vesting = project.VestingEscrowLL.at(vesting)
    factory.set_operator(staking, operator, True, sender=deployer)
    vesting.set_operator(operator, True, sender=alice)
    assert delegate_registry.delegation(vesting, delegation_space) == ZERO_ADDRESS
    operator.set_snapshot_delegate(vesting, bob, sender=alice)
    assert delegate_registry.delegation(vesting, delegation_space) == bob

def test_set_snapshot_delegate_permission(ychad, deployer, alice, bob, locking_token, staking, factory, depositor, operator):
    # only recipient can delegate voting weight
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    factory.create_vest(alice, 3 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    vesting, _ = factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice).return_value
    vesting = project.VestingEscrowLL.at(vesting)
    factory.set_operator(staking, operator, True, sender=deployer)
    vesting.set_operator(operator, True, sender=alice)
    with reverts():
        operator.set_snapshot_delegate(vesting, bob, sender=deployer)

def test_unset_snapshot_delegate(ychad, deployer, alice, bob, locking_token, staking, factory, depositor, operator, delegate_registry, delegation_space):
    # snapshot voting weight can be undelegated
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    factory.create_vest(alice, 3 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    vesting, _ = factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice).return_value
    vesting = project.VestingEscrowLL.at(vesting)
    factory.set_operator(staking, operator, True, sender=deployer)
    vesting.set_operator(operator, True, sender=alice)
    operator.set_snapshot_delegate(vesting, bob, sender=alice)
    assert delegate_registry.delegation(vesting, delegation_space) == bob
    operator.set_snapshot_delegate(vesting, ZERO_ADDRESS, sender=alice)
    assert delegate_registry.delegation(vesting, delegation_space) == ZERO_ADDRESS

def test_lock(chain, ychad, deployer, alice, locking_token, staking, factory, depositor, operator):
    # stake can be locked by calling the operator
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    factory.create_vest(alice, 3 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    vesting, _ = factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice).return_value
    vesting = project.VestingEscrowLL.at(vesting)
    factory.set_operator(staking, operator, True, sender=deployer)
    vesting.set_operator(operator, True, sender=alice)
    assert staking.unlock_times(vesting) == 0
    ts = chain.pending_timestamp
    operator.lock(vesting, WEEK, sender=alice)
    assert staking.unlock_times(vesting) == ts + WEEK

def test_lock_permission(ychad, deployer, alice, locking_token, staking, factory, depositor, operator):
    # only recipient can lock
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    factory.create_vest(alice, 3 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    vesting, _ = factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice).return_value
    vesting = project.VestingEscrowLL.at(vesting)
    factory.set_operator(staking, operator, True, sender=deployer)
    vesting.set_operator(operator, True, sender=alice)
    with reverts():
        operator.lock(vesting, WEEK, sender=deployer)

def test_claim(chain, ychad, deployer, alice, bob, locking_token, proxy, staking, rewards, factory, depositor, operator):
    # rewards can be claimed by calling the operator
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    factory.create_vest(alice, 3 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    vesting, _ = factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice).return_value
    vesting = project.VestingEscrowLL.at(vesting)
    factory.set_operator(staking, operator, True, sender=deployer)
    vesting.set_operator(operator, True, sender=alice)

    locking_token.transfer(proxy, UNIT, sender=ychad)
    rewards.harvest(UNIT, 0, sender=deployer)
    chain.pending_timestamp += WEEK
    operator.claim(vesting, bob, sender=alice)
    assert locking_token.balanceOf(bob) > 0

def test_claim_permission(chain, ychad, deployer, alice, locking_token, proxy, staking, rewards, factory, depositor, operator):
    # only recipient can claim rewards
    locking_token.approve(factory, 3 * UNIT, sender=ychad)
    factory.create_vest(alice, 3 * UNIT, 5 * DAY, sender=ychad)
    factory.set_liquid_locker(staking, depositor, sender=deployer)
    vesting, _ = factory.deploy_vesting_contract(0, staking, UNIT, False, sender=alice).return_value
    vesting = project.VestingEscrowLL.at(vesting)
    factory.set_operator(staking, operator, True, sender=deployer)
    vesting.set_operator(operator, True, sender=alice)

    locking_token.transfer(proxy, UNIT, sender=ychad)
    rewards.harvest(UNIT, 0, sender=deployer)
    chain.pending_timestamp += WEEK
    with reverts():
        operator.claim(vesting, sender=deployer)
