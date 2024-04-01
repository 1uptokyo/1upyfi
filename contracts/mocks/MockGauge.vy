# @version 0.3.10

from vyper.interfaces import ERC20

asset: public(immutable(address))
ygauge: public(immutable(address))

@external
def __init__(_asset: address, _ygauge: address):
    asset = _asset
    ygauge  = _ygauge
