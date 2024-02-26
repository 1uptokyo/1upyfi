# @version 0.3.10

interface YearnRegistry:
    def registered(_ygauge: address) -> bool: view

interface Registry:
    def register(_gauge: address) -> uint256: nonpayable

yearn_registry: public(immutable(YearnRegistry))
reward_token: public(immutable(address))
proxy: public(immutable(address))
registry: public(immutable(Registry))
rewards: public(immutable(address))

management: public(address)
pending_management: public(address)
gauge_blueprint: public(address)

event SetGaugeBlueprint:
    blueprint: address

event PendingManagement:
    management: address

event SetManagement:
    management: address

@external
def __init__(_yearn_registry: address, _reward_token: address, _proxy: address, _registry: address, _rewards: address):
    yearn_registry = YearnRegistry(_yearn_registry)
    reward_token = _reward_token
    proxy = _proxy
    registry = Registry(_registry)
    rewards = _rewards

    self.management = msg.sender

@external
def deploy_gauge(_ygauge: address) -> address:
    assert yearn_registry.registered(_ygauge)
    blueprint: address = self.gauge_blueprint
    assert blueprint != empty(address)

    gauge: address = create_from_blueprint(
        blueprint,
        _ygauge,
        proxy,
        reward_token,
        rewards,
        code_offset=3
    )
    registry.register(gauge)
    return gauge

@external
def set_gauge_blueprint(_blueprint: address):
    assert msg.sender == self.management
    assert _blueprint != empty(address)
    self.gauge_blueprint = _blueprint
    log SetGaugeBlueprint(_blueprint)

@external
def set_management(_management: address):
    """
    @notice 
        Set the pending management address.
        Needs to be accepted by that account separately to transfer management over
    @param _management New pending management address
    """
    assert msg.sender == self.management
    self.pending_management = _management
    log PendingManagement(_management)

@external
def accept_management():
    """
    @notice 
        Accept management role.
        Can only be called by account previously marked as pending management by current management
    """
    assert msg.sender == self.pending_management
    self.pending_management = empty(address)
    self.management = msg.sender
    log SetManagement(msg.sender)
