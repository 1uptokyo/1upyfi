# @version 0.3.10

interface YearnRegistry:
    def registered(_ygauge: address) -> bool: view

implements: YearnRegistry

registered: public(HashMap[address, bool])

@external
def set_registered(_ygauge: address, _registered: bool):
    self.registered[_ygauge] = _registered
