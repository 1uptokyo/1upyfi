from ape import reverts
from ape import Contract
from pytest import fixture
from _constants import _deploy_blueprint, ZERO_ADDRESS

YGAUGE = '0x7Fd8Af959B54A677a1D8F92265Bd0714274C56a3' # YFI/ETH yGauge

@fixture
def collector(accounts):
    return accounts[3]

@fixture
def yearn_registry(project, deployer):
    return project.MockYearnRegistry.deploy(sender=deployer)

@fixture
def ygauge(deployer, yearn_registry):
    ygauge = Contract(YGAUGE)
    yearn_registry.set_registered(ygauge, True, sender=deployer)
    return ygauge

@fixture
def reward_token(project, deployer):
    return project.MockToken.deploy(sender=deployer)

@fixture
def registry(project, deployer, proxy):
    registry = project.Registry.deploy(proxy, sender=deployer)
    proxy.set_operator(registry, True, sender=deployer)
    return registry

@fixture
def blueprint(project, deployer):
    return _deploy_blueprint(project.Gauge, deployer)

@fixture
def factory(project, deployer, proxy, collector, yearn_registry, reward_token, registry, blueprint):
    factory = project.Factory.deploy(yearn_registry, reward_token, proxy, registry, collector, sender=deployer)
    factory.set_gauge_blueprint(blueprint, sender=deployer)
    registry.set_registrar(factory, sender=deployer)
    return factory

def test_deploy(project, alice, ygauge, registry, factory):
    assert registry.num_gauges() == 0
    assert registry.gauge_map(ygauge) == ZERO_ADDRESS
    gauge = factory.deploy_gauge(ygauge, sender=alice).return_value
    gauge = project.Gauge.at(gauge)
    assert registry.num_gauges() == 1
    assert registry.gauge_map(ygauge) == gauge
    assert gauge.name() == '1up Curve YFI-ETH Pool yVault'
    assert gauge.symbol() == '1up-yvCurve-YFIETH'

def test_deploy_again(alice, ygauge, factory):
    # cant deploy a gauge for the same ygauge again
    factory.deploy_gauge(ygauge, sender=alice)
    with reverts():
        factory.deploy_gauge(ygauge, sender=alice)

def test_set_blueprint(project, deployer, blueprint, factory):
    new_blueprint = _deploy_blueprint(project.Gauge, deployer)
    assert factory.gauge_blueprint() == blueprint
    factory.set_gauge_blueprint(new_blueprint, sender=deployer)
    assert factory.gauge_blueprint() == new_blueprint

def test_set_blueprint_permission(project, alice, factory):
    new_blueprint = _deploy_blueprint(project.Gauge, alice)
    with reverts():
        factory.set_gauge_blueprint(new_blueprint, sender=alice)

def test_set_management(deployer, alice, factory):
    assert factory.management() == deployer
    assert factory.pending_management() == ZERO_ADDRESS
    factory.set_management(alice, sender=deployer)
    assert factory.management() == deployer
    assert factory.pending_management() == alice

def test_set_management_undo(deployer, alice, factory):
    factory.set_management(alice, sender=deployer)
    factory.set_management(ZERO_ADDRESS, sender=deployer)
    assert factory.management() == deployer
    assert factory.pending_management() == ZERO_ADDRESS

def test_set_management_permission(alice, factory):
    with reverts():
        factory.set_management(alice, sender=alice)

def test_accept_management(deployer, alice, factory):
    factory.set_management(alice, sender=deployer)
    factory.accept_management(sender=alice)
    assert factory.management() == alice
    assert factory.pending_management() == ZERO_ADDRESS

def test_accept_management_early(alice, factory):
    # cant accept management role without being nominated
    with reverts():
        factory.accept_management(sender=alice)

def test_accept_management_wrong(deployer, alice, bob, factory):
    # cant accept management role without being the nominee
    factory.set_management(alice, sender=deployer)
    with reverts():
        factory.accept_management(sender=bob)
