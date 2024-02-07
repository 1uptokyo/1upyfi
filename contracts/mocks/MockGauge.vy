# @version 0.3.10

from vyper.interfaces import ERC20

rewards: immutable(ERC20)

@external
def __init__(_rewards: address, _collector: address):
    rewards = ERC20(_rewards)
    assert rewards.approve(_collector, max_value(uint256), default_return_value=True)

@external
def harvest() -> uint256:
    return rewards.balanceOf(self)
