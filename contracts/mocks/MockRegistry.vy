# @version 0.3.10

interface Registry:
    def gauge_map(_ygauge: address) -> address: view
implements: Registry

gauge_map: public(HashMap[address, address])

@external
def set_gauge_map(_ygauge: address, _gauge: address):
    self.gauge_map[_ygauge] = _gauge
