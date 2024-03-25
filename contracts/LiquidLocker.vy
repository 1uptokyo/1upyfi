# @version 0.3.10
"""
@title Liquid locker
@author 1up
@license GNU AGPLv3
@notice
    Tokenization of protocol's voting escrow position.
    Mints a fixed amount of tokens per token locked in the voting escrow.
    Intended to be a proxy operator.
"""

from vyper.interfaces import ERC20
implements: ERC20

interface Proxy:
    def modify_lock(_amount: uint256, _unlock_time: uint256): nonpayable

interface YearnVotingEscrow:
    def locked(_account: address) -> uint256: view

token: public(immutable(ERC20))
voting_escrow: public(immutable(YearnVotingEscrow))
proxy: public(immutable(Proxy))

totalSupply: public(uint256)
balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])

decimals: public(constant(uint8)) = 18
name: public(constant(String[14])) = "1UP Locked YFI"
symbol: public(constant(String[5])) = "upYFI"

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

SCALE: constant(uint256) = 69_420
WEEK: constant(uint256) = 7 * 24 * 60 * 60
LOCK_TIME: constant(uint256) = 500 * WEEK

@external
def __init__(_token: address, _voting_escrow: address, _proxy: address):
    """
    @notice Constructor
    @param _token Token to be locked in the voting escrow
    @param _voting_escrow Voting escrow
    @param _proxy Proxy
    """
    token = ERC20(_token)
    voting_escrow = YearnVotingEscrow(_voting_escrow)
    proxy = Proxy(_proxy)
    log Transfer(empty(address), msg.sender, 0)

@external
def deposit(_amount: uint256, _receiver: address = msg.sender) -> uint256:
    """
    @notice Deposit tokens into the protocol's ve position and mint liquid locker tokens
    @param _amount Amount of tokens to add to the lock
    @param _receiver Recipient of newly minted liquid locker tokens
    @return Amount of tokens minted to the recipient
    """
    minted: uint256 = _amount * SCALE
    self._mint(minted, _receiver)
    assert token.transferFrom(msg.sender, proxy.address, _amount, default_return_value=True)
    proxy.modify_lock(_amount, block.timestamp + LOCK_TIME)
    return minted

@external
def mint(_receiver: address = msg.sender) -> uint256:
    """
    @notice Mint liquid locker tokens for any new tokens in the ve lock
    @param _receiver Receiver of newly minted liquid locker tokens
    @return Amount of tokens minted to the recipient
    """
    excess: uint256 = voting_escrow.locked(proxy.address) * SCALE - self.totalSupply
    self._mint(excess, _receiver)
    return excess

@internal
def _mint(_amount: uint256, _receiver: address):
    """
    @notice Mint an amount of liquid locker tokens
    """
    assert _amount > 0
    assert _receiver != empty(address)

    self.totalSupply += _amount
    self.balanceOf[_receiver] += _amount
    log Transfer(empty(address), _receiver, _amount)

@external
def extend_lock():
    """
    @notice Extend the duration of the protocol's ve lock
    """
    proxy.modify_lock(0, block.timestamp + LOCK_TIME)

@external
def transfer(_to: address, _value: uint256) -> bool:
    """
    @notice Transfer tokens
    @param _to Receiver of tokens
    @param _value Amount of tokens to transfer
    """
    assert _to != empty(address) and _to != self

    self.balanceOf[msg.sender] -= _value
    self.balanceOf[_to] += _value
    log Transfer(msg.sender, _to, _value)
    return True

@external
def transferFrom(_from: address, _to: address, _value: uint256) -> bool:
    """
    @notice Transfer tokens from another user
    @param _from User to transfer tokens from 
    @param _to Receiver of tokens
    @param _value Amount of tokens to transfer
    @dev Requires prior set allowance
    """
    assert _to != empty(address) and _to != self

    if _value > 0:
        allowance: uint256 = self.allowance[_from][msg.sender] - _value
        self.allowance[_from][msg.sender] = allowance

    self.balanceOf[_from] -= _value
    self.balanceOf[_to] += _value
    log Transfer(_from, _to, _value)
    return True

@external
def approve(_spender: address, _value: uint256) -> bool:
    """
    @notice Approve another user to spend your tokens
    @param _spender Spender
    @param _value Amount of tokens allowed to be spent
    """
    assert _spender != empty(address)

    self.allowance[msg.sender][_spender] = _value
    log Approval(msg.sender, _spender, _value)
    return True
