# @version 0.3.10
"""
@title Gauge registry
@author 1up
@license GNU AGPLv3
@notice
    Tracks the registered protocol gauges and the underlying Yearn gauges.
    A Yearn gauge can have at most one protocol gauge in the registry.
    Intended to be a proxy operator.
"""

interface Registry:
    def num_gauges() -> uint256: view
    def ygauges(_idx: uint256) -> address: view
    def gauges(_idx: uint256) -> address: view
    def gauge_map(_ygauge: address) -> address: view
implements: Registry

interface Gauge:
    def asset() -> address: view

interface Proxy:
    def call(_target: address, _data: Bytes[68]): nonpayable

proxy: public(immutable(Proxy))
management: public(address)
pending_management: public(address)
registrar: public(address)

num_gauges: public(uint256)
ygauges: public(address[MAX_NUM_GAUGES])
gauge_map: public(HashMap[address, address]) # ygauge => gauge

MAX_NUM_GAUGES: constant(uint256) = 99999
YGAUGE_DISABLED: constant(address) = 0x0000000000000000000000000000000000000001

event Register:
    gauge: indexed(address)
    ygauge: indexed(address)
    idx: uint256

event Deregister:
    gauge: indexed(address)
    ygauge: indexed(address)
    idx: indexed(uint256)

event NewIndex:
    old_idx: indexed(uint256)
    new_idx: uint256

event Disable:
    ygauge: indexed(address)
    disabled: bool

event SetRegistrar:
    registrar: address

event PendingManagement:
    management: address

event SetManagement:
    management: address

@external
def __init__(_proxy: address):
    """
    @notice Constructor
    @param _proxy Proxy
    """
    proxy = Proxy(_proxy)
    self.management = msg.sender
    self.registrar = msg.sender

@external
@view
def gauges(_idx: uint256) -> address:
    """
    @notice Get the gauge at a certain index
    @param _idx Index of the gauge
    @return Gauge address
    """
    assert _idx < self.num_gauges
    ygauge: address = self.ygauges[_idx]
    assert ygauge != empty(address)
    return self.gauge_map[ygauge]

@external
@view
def gauge_registered(_gauge: address) -> bool:
    """
    @notice Check whether a gauge is registered or not
    @param _gauge Gauge address
    @return True: gauge is registered, False: gauge is not registered
    """
    ygauge: address = Gauge(_gauge).asset()
    return self.gauge_map[ygauge] == _gauge

@external
@view
def ygauge_registered(_ygauge: address) -> bool:
    """
    @notice Check whether a Yearn gauge is registered or not
    @param _ygauge Yearn gauge address
    @return True: Yearn gauge is registered, False: Yearn gauge is not registered
    """
    gauge: address = self.gauge_map[_ygauge]
    return gauge != empty(address) and gauge != YGAUGE_DISABLED

@external
def register(_gauge: address) -> uint256:
    """
    @notice Register a gauge
    @param _gauge Gauge address
    @return Index of the newly registered gauge
    @dev Can only be called by the registrar
    @dev The underlying Yearn gauge cannot already be in the registry
    """
    assert msg.sender == self.registrar
    ygauge: address = Gauge(_gauge).asset()
    assert ygauge != empty(address)
    assert self.gauge_map[ygauge] == empty(address)

    idx: uint256 = self.num_gauges
    assert idx < MAX_NUM_GAUGES
    self.num_gauges = idx + 1
    self.ygauges[idx] = ygauge
    self.gauge_map[ygauge] = _gauge

    # approve gauge to transfer ygauge tokens out of proxy
    data: Bytes[68] = _abi_encode(_gauge, max_value(uint256), method_id=method_id("approve(address,uint256)"))
    proxy.call(ygauge, data)

    # set gauge as recipient of rewards
    data = _abi_encode(_gauge, method_id=method_id("setRecipient(address)"))
    proxy.call(ygauge, data)

    log Register(_gauge, ygauge, idx)
    return idx

@external
def deregister(_gauge: address, _idx: uint256):
    """
    @notice Deregister a gauge
    @param _gauge Gauge address
    @param _idx Gauge index
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    ygauge: address = Gauge(_gauge).asset()
    assert self.gauge_map[ygauge] == _gauge
    assert self.ygauges[_idx] == ygauge

    # swap last entry in array with the one being deleted
    # and shorten array by one
    max_idx: uint256 = self.num_gauges - 1
    self.num_gauges = max_idx
    log Deregister(_gauge, ygauge, _idx)
    if _idx != max_idx:
        self.ygauges[_idx] = self.ygauges[max_idx]
        log NewIndex(max_idx, _idx)
    self.ygauges[max_idx] = empty(address)
    self.gauge_map[ygauge] = empty(address)

@external
@view
def disabled(_ygauge: address) -> bool:
    """
    @notice Check whether a Yearn gauge is disabled or not
    @param _ygauge Yearn gauge address
    @return True: disabled, False: enabled
    """
    return self.gauge_map[_ygauge] == YGAUGE_DISABLED

@external
def disable(_ygauge: address, _disabled: bool):
    """
    @notice Disable a Yearn gauge, preventing it from being registered
    @param _ygauge Yearn gauge address
    @param _disabled True: disabled, False: enabled
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _ygauge != empty(address)
    if _disabled:
        assert self.gauge_map[_ygauge] == empty(address)
        self.gauge_map[_ygauge] = YGAUGE_DISABLED
    else:
        assert self.gauge_map[_ygauge] == YGAUGE_DISABLED
        self.gauge_map[_ygauge] = empty(address)
    log Disable(_ygauge, _disabled)

@external
def set_registrar(_registrar: address):
    """
    @notice Set new registrar
    @param _registrar Registrar
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    self.registrar = _registrar
    log SetRegistrar(_registrar)

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
