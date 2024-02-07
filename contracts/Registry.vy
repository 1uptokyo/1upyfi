# @version 0.3.10

interface Gauge:
    def asset() -> address: view

interface Proxy:
    def call(_target: address, _data: Bytes[68]): nonpayable

proxy: public(immutable(Proxy))
management: public(address)
registrar: public(address)

ygauge_count: public(uint256)
ygauges: public(address[99999])
ygauge_map: public(HashMap[address, address]) # ygauge => gauge

event Register:
    gauge: indexed(address)
    idx: uint256

event Deregister:
    gauge: indexed(address)
    idx: uint256

@external
def __init__(_proxy: address):
    proxy = Proxy(_proxy)
    self.management = msg.sender
    self.registrar = msg.sender

@external
def register(_gauge: address) -> uint256:
    assert msg.sender == self.registrar
    ygauge: address = Gauge(_gauge).asset()
    assert self.ygauge_map[ygauge] == empty(address)

    idx: uint256 = self.ygauge_count
    self.ygauge_count = idx + 1
    self.ygauges[idx] = ygauge
    self.ygauge_map[ygauge] = _gauge

    # approve gauge to transfer ygauge tokens out of proxy
    data: Bytes[68] = _abi_encode(_gauge, max_value(uint256), method_id=method_id("approve(address,uint256)"))
    proxy.call(ygauge, data)

    # set gauge as recipient of rewards
    data = _abi_encode(_gauge, method_id=method_id("setRecipient(address)"))
    proxy.call(ygauge, data)

    log Register(_gauge, idx)
    return idx

@external
def deregister(_gauge: address, _idx: uint256):
    assert msg.sender == self.management
    ygauge: address = Gauge(_gauge).asset()
    assert self.ygauge_map[ygauge] == _gauge
    assert self.ygauges[_idx] == ygauge

    # swap last entry in array with the one being deleted
    # and shorten array by one
    max_idx: uint256 = self.ygauge_count - 1
    self.ygauge_count = max_idx
    if _idx != max_idx:
        self.ygauges[_idx] = self.ygauges[max_idx]
    self.ygauges[max_idx] = empty(address)
    self.ygauge_map[ygauge] = empty(address)
    log Deregister(_gauge, _idx)
