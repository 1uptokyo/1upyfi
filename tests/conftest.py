from ape import Contract
from pytest import fixture
from _constants import *

@fixture
def deployer(accounts):
    return accounts[0]

@fixture
def alice(accounts):
    return accounts[1]

@fixture
def bob(accounts):
    return accounts[2]

@fixture
def ychad(accounts):
    return accounts[YCHAD]

@fixture
def locking_token():
    return Contract(YFI)

@fixture
def voting_escrow():
    return Contract(VEYFI)

@fixture
def discount_token():
    return Contract(DYFI)

@fixture
def proxy(project, deployer, locking_token, voting_escrow):
    proxy = project.Proxy.deploy(voting_escrow, sender=deployer)
    data = locking_token.approve.encode_input(voting_escrow, MAX_VALUE)
    proxy.call(locking_token, data, sender=deployer)
    return proxy

@fixture
def liquid_locker(project, deployer, locking_token, voting_escrow, proxy):
    locker = project.LiquidLocker.deploy(locking_token, voting_escrow, proxy, sender=deployer)
    proxy.set_operator(locker, True, sender=deployer)
    return locker
