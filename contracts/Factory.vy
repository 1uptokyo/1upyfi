# @version 0.3.10

interface YearnRegistry:
    def registered(_ygauge: address) -> bool: view

interface Registry:
    def register(_gauge: address) -> uint256: nonpayable

yearn_registry: public(immutable(YearnRegistry))
reward: public(immutable(address))
proxy: public(immutable(address))
registry: public(immutable(Registry))
collector: public(immutable(address))

management: public(address)
pending_management: public(address)
gauge_implementation: public(address)

@external
def __init__(_yearn_registry: address, _reward: address, _proxy: address, _registry: address, _collector: address):
    yearn_registry = YearnRegistry(_yearn_registry)
    reward = _reward
    proxy = _proxy
    registry = Registry(_registry)
    collector = _collector

    self.management = msg.sender

@external
def deploy_gauge(_ygauge: address) -> address:
    assert yearn_registry.registered(_ygauge)
    implementation: address = self.gauge_implementation
    assert implementation != empty(address)

    gauge: address = create_from_blueprint(
        implementation,
        _ygauge,
        proxy,
        reward,
        collector,
        code_offset=3
    )
    registry.register(gauge)
    return gauge
