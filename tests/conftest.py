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
def yfi():
    return Contract(YFI)

@fixture
def veyfi():
    return Contract(VEYFI)

@fixture
def proxy(project, deployer, veyfi):
    return project.Proxy.deploy(veyfi, sender=deployer)
