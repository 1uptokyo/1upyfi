from ape import reverts
from _constants import *

MESSAGE_HASH = '0x0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF'
EIP1271_MAGIC_VALUE = 0x1626ba7e

def test_proxy_call(project, deployer, alice, proxy):
    # operator can call any contract through the proxy
    proxy.set_operator(alice, True, sender=deployer)
    token = project.MockToken.deploy(sender=deployer)
    token.mint(proxy, UNIT, sender=deployer)
    data = token.transfer.encode_input(alice, UNIT)
    proxy.call(token, data, sender=alice)
    assert token.balanceOf(alice) == UNIT

def test_proxy_call_permission(project, deployer, alice, proxy):
    # only operator can call a contract through the proxy
    token = project.MockToken.deploy(sender=deployer)
    token.mint(proxy, UNIT, sender=deployer)
    data = token.transfer.encode_input(alice, UNIT)
    with reverts():
        proxy.call(token, data, sender=alice)

def test_modify_lock(chain, deployer, alice, ychad, locking_token, voting_escrow, proxy):
    # modify proxy's lock
    data = locking_token.approve.encode_input(voting_escrow, MAX_VALUE)
    proxy.call(locking_token, data, sender=deployer)
    locking_token.transfer(proxy, UNIT, sender=ychad)
    proxy.set_operator(alice, True, sender=deployer)
    proxy.modify_lock(UNIT, chain.pending_timestamp + 500 * 7 * 24 * 60 * 60, sender=alice)
    assert locking_token.balanceOf(proxy) == 0

def test_modify_lock_permission(chain, deployer, alice, ychad, locking_token, voting_escrow, proxy):
    # only operator can modify lock
    data = locking_token.approve.encode_input(voting_escrow, MAX_VALUE)
    proxy.call(locking_token, data, sender=deployer)
    locking_token.transfer(proxy, UNIT, sender=ychad)
    with reverts():
        proxy.modify_lock(UNIT, chain.pending_timestamp + 500 * 7 * 24 * 60 * 60, sender=alice)

def test_set_signed_message(deployer, alice, proxy):
    # set a EIP-1271 signed message
    proxy.set_operator(alice, True, sender=deployer)
    with reverts():
        proxy.isValidSignature(MESSAGE_HASH, b"")
    proxy.set_signed_message(MESSAGE_HASH, True, sender=alice)
    assert proxy.isValidSignature(MESSAGE_HASH, b"") == EIP1271_MAGIC_VALUE

def test_unset_signed_message(deployer, alice, proxy):
    # unset a EIP-1271 signed message
    proxy.set_operator(alice, True, sender=deployer)
    proxy.set_signed_message(MESSAGE_HASH, True, sender=alice)
    proxy.set_signed_message(MESSAGE_HASH, False, sender=alice)
    with reverts():
        proxy.isValidSignature(MESSAGE_HASH, b"")

def test_set_signed_message_permission(alice, proxy):
    # only an operator can set a signed message
    with reverts():
        proxy.set_signed_message(MESSAGE_HASH, True, sender=alice)

def test_proxy_set_operator(deployer, alice, proxy):
    # add an operator
    assert not proxy.operators(alice)
    proxy.set_operator(alice, True, sender=deployer)
    assert proxy.operators(alice)

def test_proxy_unset_operator(deployer, alice, proxy):
    # remove an operator
    proxy.set_operator(alice, True, sender=deployer)
    assert proxy.operators(alice)
    proxy.set_operator(alice, False, sender=deployer)
    assert not proxy.operators(alice)

def test_proxy_set_operator_permission(alice, proxy):
    # only management can change operator status
    with reverts():
        proxy.set_operator(alice, True, sender=alice)

def test_set_management(deployer, alice, proxy):
    # management can propose a replacement
    assert proxy.management() == deployer
    assert proxy.pending_management() == ZERO_ADDRESS
    proxy.set_management(alice, sender=deployer)
    assert proxy.management() == deployer
    assert proxy.pending_management() == alice

def test_set_management_undo(deployer, alice, proxy):
    # proposed replacement can be undone
    proxy.set_management(alice, sender=deployer)
    proxy.set_management(ZERO_ADDRESS, sender=deployer)
    assert proxy.management() == deployer
    assert proxy.pending_management() == ZERO_ADDRESS

def test_set_management_permission(alice, proxy):
    # only management can propose a replacement
    with reverts():
        proxy.set_management(alice, sender=alice)

def test_accept_management(deployer, alice, proxy):
    # replacement can accept management role
    proxy.set_management(alice, sender=deployer)
    proxy.accept_management(sender=alice)
    assert proxy.management() == alice
    assert proxy.pending_management() == ZERO_ADDRESS

def test_accept_management_early(alice, proxy):
    # cant accept management role without being nominated
    with reverts():
        proxy.accept_management(sender=alice)

def test_accept_management_wrong(deployer, alice, bob, proxy):
    # cant accept management role without being the nominee
    proxy.set_management(alice, sender=deployer)
    with reverts():
        proxy.accept_management(sender=bob)
