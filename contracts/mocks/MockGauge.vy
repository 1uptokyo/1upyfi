# @version 0.3.10

from vyper.interfaces import ERC20

asset: public(immutable(address))
rewards: immutable(ERC20)

@external
def __init__(_asset: address, _rewards: address):
    asset = _asset
    rewards = ERC20(_rewards)

# @external
# def approve(_collector: address):
#     assert rewards.approve(_collector, max_value(uint256), default_return_value=True)

# @external
# def harvest() -> uint256:
#     return rewards.balanceOf(self)
