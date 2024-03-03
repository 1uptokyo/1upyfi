from ape import reverts
from pytest import fixture
from _constants import *

@fixture
def registrar(accounts):
    return accounts[3]

@fixture
def registry(project, deployer, registrar, proxy):
    registry = project.Registry.deploy(proxy, sender=deployer)
    registry.set_registrar(registrar, sender=deployer)
    proxy.set_operator(registry, True, sender=deployer)
    return registry

@fixture
def ygauge(project, deployer):
    return project.MockYearnGauge.deploy(sender=deployer)

@fixture
def gauge(project, deployer, ygauge):
    return project.MockGauge.deploy(ygauge, sender=deployer)

def test_register(registrar, registry, ygauge, gauge):
    # register a gauge
    assert registry.num_gauges() == 0
    assert registry.ygauges(0) == ZERO_ADDRESS
    with reverts():
        registry.gauges(0)
    assert registry.gauge_map(ygauge) == ZERO_ADDRESS
    assert registry.register(gauge, sender=registrar).return_value == 0
    assert registry.num_gauges() == 1
    assert registry.ygauges(0) == ygauge
    assert registry.gauges(0) == gauge
    assert registry.gauge_map(ygauge) == gauge

def test_register_permission(deployer, registry, gauge):
    # only registrar can register a gauge
    with reverts():
        registry.register(gauge, sender=deployer)

def test_register_again(registrar, registry, gauge):
    # cant register same gauge again
    registry.register(gauge, sender=registrar)
    with reverts():
        registry.register(gauge, sender=registrar)

def test_register_double(project, deployer, registrar, registry, ygauge, gauge):
    # cant register another gauge with same ygauge
    registry.register(gauge, sender=registrar)
    gauge2 = project.MockGauge.deploy(ygauge, sender=deployer)
    with reverts():
        registry.register(gauge2, sender=registrar)

def test_deregister(project, deployer, registrar, registry, ygauge, gauge):
    # deregister a gauge
    ygauge2 = project.MockYearnGauge.deploy(sender=deployer)
    gauge2 = project.MockGauge.deploy(ygauge2, sender=deployer)
    registry.register(gauge, sender=registrar)
    registry.register(gauge2, sender=registrar)
    assert registry.num_gauges() == 2
    assert registry.ygauges(0) == ygauge
    assert registry.ygauges(1) == ygauge2
    assert registry.gauges(0) == gauge
    assert registry.gauges(1) == gauge2
    assert registry.gauge_map(ygauge) == gauge
    assert registry.gauge_map(ygauge2) == gauge2
    registry.deregister(gauge, 0, sender=deployer)
    assert registry.num_gauges() == 1
    assert registry.ygauges(0) == ygauge2
    assert registry.ygauges(1) == ZERO_ADDRESS
    assert registry.gauges(0) == gauge2
    with reverts():
        registry.gauges(1)
    assert registry.gauge_map(ygauge) == ZERO_ADDRESS

def test_deregister_last(project, deployer, registrar, registry, ygauge, gauge):
    # deregister last registered gauge - update array correctly
    ygauge2 = project.MockYearnGauge.deploy(sender=deployer)
    gauge2 = project.MockGauge.deploy(ygauge2, sender=deployer)
    registry.register(gauge, sender=registrar)
    registry.register(gauge2, sender=registrar)
    registry.deregister(gauge2, 1, sender=deployer)
    assert registry.num_gauges() == 1
    assert registry.ygauges(0) == ygauge
    assert registry.ygauges(1) == ZERO_ADDRESS
    assert registry.gauges(0) == gauge
    with reverts():
        registry.gauges(1)
    assert registry.gauge_map(ygauge2) == ZERO_ADDRESS

def test_deregister_permission(registrar, registry, gauge):
    # only management can deregister a gauge
    registry.register(gauge, sender=registrar)
    with reverts():
        registry.deregister(gauge, 0, sender=registrar)

def test_deregister_not_registered(project, deployer, registrar, registry, gauge):
    # cant deregister a gauge that isnt registered
    ygauge2 = project.MockYearnGauge.deploy(sender=deployer)
    gauge2 = project.MockGauge.deploy(ygauge2, sender=deployer)
    registry.register(gauge, sender=registrar)
    with reverts():
        registry.deregister(gauge2, 1, sender=deployer)

def test_deregister_wrong(project, deployer, registrar, registry, ygauge, gauge):
    # cant deregister a non-registered gauge that has a registered ygauge
    gauge2 = project.MockGauge.deploy(ygauge, sender=deployer)
    registry.register(gauge, sender=registrar)
    with reverts():
        registry.deregister(gauge2, 0, sender=deployer)

def test_deregister_idx(project, deployer, registrar, registry, gauge):
    # cant deregister with wrong index
    ygauge2 = project.MockYearnGauge.deploy(sender=deployer)
    gauge2 = project.MockGauge.deploy(ygauge2, sender=deployer)
    registry.register(gauge, sender=registrar)
    registry.register(gauge2, sender=registrar)
    with reverts():
        registry.deregister(gauge, 1, sender=deployer)

def test_set_registrar(deployer, alice, registrar, registry):
    # set new registrar address
    assert registry.registrar() == registrar
    registry.set_registrar(alice, sender=deployer)
    assert registry.registrar() == alice

def test_set_registrar_permission(alice, registry):
    # only management can set new registrar
    with reverts():
        registry.set_registrar(alice, sender=alice)

def test_set_management(deployer, alice, registry):
    # management can propose a replacement
    assert registry.management() == deployer
    assert registry.pending_management() == ZERO_ADDRESS
    registry.set_management(alice, sender=deployer)
    assert registry.management() == deployer
    assert registry.pending_management() == alice

def test_set_management_undo(deployer, alice, registry):
    # proposed replacement can be undone
    registry.set_management(alice, sender=deployer)
    registry.set_management(ZERO_ADDRESS, sender=deployer)
    assert registry.management() == deployer
    assert registry.pending_management() == ZERO_ADDRESS

def test_set_management_permission(alice, registry):
    # only management can propose a replacement
    with reverts():
        registry.set_management(alice, sender=alice)

def test_accept_management(deployer, alice, registry):
    # replacement can accept management role
    registry.set_management(alice, sender=deployer)
    registry.accept_management(sender=alice)
    assert registry.management() == alice
    assert registry.pending_management() == ZERO_ADDRESS

def test_accept_management_early(alice, registry):
    # cant accept management role without being nominated
    with reverts():
        registry.accept_management(sender=alice)

def test_accept_management_wrong(deployer, alice, bob, registry):
    # cant accept management role without being the nominee
    registry.set_management(alice, sender=deployer)
    with reverts():
        registry.accept_management(sender=bob)
