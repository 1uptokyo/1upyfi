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
def reward_token():
    return Contract(DYFI)

@fixture
def proxy(project, deployer, voting_escrow):
    return project.Proxy.deploy(voting_escrow, sender=deployer)
