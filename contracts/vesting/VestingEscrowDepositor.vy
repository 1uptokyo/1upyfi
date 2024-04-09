# @version 0.3.10

"""
@title 1UP depositor
@author 1UP
@license MIT
@notice Deposits YFI into the 1UP liquid locker and stakes the tokens to receive supYFI
@dev Intended to be used as depositor inside `VotingEscrowFactory`
"""

from vyper.interfaces import ERC20
from vyper.interfaces import ERC4626

interface Depositor:
    def deposit(_amount: uint256) -> uint256: nonpayable
implements: Depositor

locking_token: public(immutable(ERC20))
liquid_locker: public(immutable(Depositor))
staking: public(immutable(ERC4626))
owner: public(immutable(address))

@external
def __init__(_locking_token: address, _liquid_locker: address, _staking: address, _owner: address):
    """
    @notice Constructor
    @param _locking_token YFI address
    @param _liquid_locker upYFI address
    @param _staking supYFI address
    @param _owner Owner address
    """
    locking_token = ERC20(_locking_token)
    liquid_locker = Depositor(_liquid_locker)
    staking = ERC4626(_staking)
    owner = _owner
    assert locking_token.approve(_liquid_locker, max_value(uint256), default_return_value=True)
    assert ERC20(_liquid_locker).approve(_staking, max_value(uint256), default_return_value=True)

@external
def deposit(_amount: uint256) -> uint256:
    """
    @notice Deposit into supYFI
    @param _amount Amount of YFI to take
    @dev Called by the factory when a vest recipient calls `deploy_vesting_contract`
    """
    assert locking_token.transferFrom(msg.sender, self, _amount, default_return_value=True)
    ll_amount: uint256 = liquid_locker.deposit(_amount)
    staking.deposit(ll_amount, msg.sender)
    return ll_amount

@external
def rescue(_token: address, _amount: uint256):
    """
    @notice Rescue tokens left in the contract on accident
    @param _token Token address
    @param _amount Amount of tokens to rescue
    """
    assert msg.sender == owner
    assert ERC20(_token).transfer(owner, _amount, default_return_value=True)
