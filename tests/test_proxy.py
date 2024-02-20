from ape import reverts
from ape.contracts import ContractInstance
from _constants import *

def test_proxy_call(project, deployer, alice, proxy):
    proxy.set_operator(alice, True, sender=deployer)
    token = project.MockToken.deploy(sender=deployer)
    token.mint(proxy, UNIT, sender=deployer)
    data = token.transfer.encode_input(alice, UNIT)
    proxy.call(token, data, sender=alice)
    assert token.balanceOf(alice) == UNIT

def test_proxy_call_permission(project, deployer, alice, proxy):
    token = project.MockToken.deploy(sender=deployer)
    token.mint(proxy, UNIT, sender=deployer)
    data = token.transfer.encode_input(alice, UNIT)
    with reverts():
        proxy.call(token, data, sender=alice)

def test_proxy_set_operator(deployer, alice, proxy):
    assert not proxy.operators(alice)
    proxy.set_operator(alice, True, sender=deployer)
    assert proxy.operators(alice)

def test_proxy_unset_operator(deployer, alice, proxy):
    proxy.set_operator(alice, True, sender=deployer)
    assert proxy.operators(alice)
    proxy.set_operator(alice, False, sender=deployer)
    assert not proxy.operators(alice)

def test_proxy_set_operator_permission(alice, proxy):
    with reverts():
        proxy.set_operator(alice, True, sender=alice)

def test_set_management(deployer, alice, proxy):
    assert proxy.management() == deployer
    assert proxy.pending_management() == ZERO_ADDRESS
    proxy.set_management(alice, sender=deployer)
    assert proxy.management() == deployer
    assert proxy.pending_management() == alice

def test_set_management_undo(deployer, alice, proxy):
    proxy.set_management(alice, sender=deployer)
    proxy.set_management(ZERO_ADDRESS, sender=deployer)
    assert proxy.management() == deployer
    assert proxy.pending_management() == ZERO_ADDRESS

def test_set_management_permission(alice, proxy):
    with reverts():
        proxy.set_management(alice, sender=alice)

def test_accept_management(deployer, alice, proxy):
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
