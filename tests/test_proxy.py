import ape
from ape.contracts import ContractInstance
from time import time
from _constants import *

def test_ownership(deployer, alice, bob, ychad, yfi, proxy):
    yfi.transfer(proxy, 2 * UNIT, sender=ychad)
    data = yfi.transfer.encode_input(alice, UNIT)

    with ape.reverts():
        proxy.call(yfi, data, sender=alice)
    with ape.reverts():
        proxy.set_operator(alice, True, sender=alice)

    proxy.set_operator(alice, True, sender=deployer)
    proxy.call(yfi, data, sender=alice)
    assert yfi.balanceOf(alice) == UNIT

    with ape.reverts():
        proxy.set_operator(bob, True, sender=alice)

    proxy.set_operator(alice, False, sender=deployer)
    with ape.reverts():
        proxy.call(yfi, data, sender=alice)

def test_lock(deployer, ychad, yfi, veyfi, proxy):
    proxy.set_operator(deployer, True, sender=deployer)
    yfi.transfer(proxy, UNIT, sender=ychad)
    data = yfi.approve.encode_input(veyfi, UNIT)
    proxy.call(yfi, data, sender=deployer)
    veyfi_proxy = ContractInstance(proxy.address, veyfi.contract_type)
    assert veyfi.balanceOf(proxy) == 0
    veyfi_proxy.modify_lock(UNIT, int(time()) + 500 * WEEK, sender=deployer)
    assert veyfi.balanceOf(proxy) > 0
