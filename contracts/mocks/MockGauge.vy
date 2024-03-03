# @version 0.3.10

from vyper.interfaces import ERC20

asset: public(immutable(address))

@external
def __init__(_asset: address):
    asset = _asset
