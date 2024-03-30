# @version 0.3.10
"""
@title Proxy
@author 1up
@license GNU AGPLv3
@notice
    Holder of protocol's voting escrow lock and yGauge tokens.
    Operators can execute arbitrary calls through the proxy.
    Supports EIP-1271 messages.
"""

interface VotingEscrow:
    def modify_lock(_amount: uint256, _unlock_time: uint256): nonpayable

implements: VotingEscrow

voting_escrow: immutable(VotingEscrow)
management: public(address)
pending_management: public(address)
operators: public(HashMap[address, bool])
messages: public(HashMap[bytes32, bool])

event Call:
    operator: indexed(address)
    target: indexed(address)

event SetSignedMessage:
    hash: indexed(bytes32)
    signed: bool

event SetOperator:
    operator: indexed(address)
    flag: bool

event PendingManagement:
    management: address

event SetManagement:
    management: address

MAX_SIZE: constant(uint256) = 1024
EIP1271_MAGIC_VALUE: constant(bytes4) = 0x1626ba7e

@external
def __init__(_voting_escrow: address):
    """
    @notice Constructor
    @param _voting_escrow Voting escrow
    """
    voting_escrow = VotingEscrow(_voting_escrow)
    self.management = msg.sender
    self.operators[msg.sender] = True

@external
@view
def isValidSignature(_hash: bytes32, _signature: Bytes[128]) -> bytes4:
    """
    @notice Check whether a message should be considered as signed
    @param _hash Hash of message
    @param _signature Signature, unused
    @return EIP-1271 magic value
    """
    assert self.messages[_hash] and len(_signature) == 0
    return EIP1271_MAGIC_VALUE

@external
@payable
def call(_target: address, _data: Bytes[MAX_SIZE]):
    """
    @notice Call another contract through the proxy
    @param _target Contract to call
    @param _data Calldata
    @dev Can only be called by operators
    """
    assert self.operators[msg.sender]
    raw_call(_target, _data, value=msg.value)
    log Call(msg.sender, _target)

@external
def modify_lock(_amount: uint256, _unlock_time: uint256):
    """
    @notice Modify the voting escrow lock
    @param _amount Amount of tokens to add to the lock
    @param _unlock_time New timestamp of unlock
    @dev Can only be called by operators
    """
    assert self.operators[msg.sender]
    voting_escrow.modify_lock(_amount, _unlock_time)

@external
def set_signed_message(_hash: bytes32, _signed: bool):
    """
    @notice Mark a message as signed
    @param _hash Message hash
    @param _signed True: signed, False; not signed
    @dev Can only be called by operators
    """
    assert self.operators[msg.sender]
    assert _hash != empty(bytes32)
    self.messages[_hash] = _signed
    log SetSignedMessage(_hash, _signed)

@external
def set_operator(_operator: address, _flag: bool):
    """
    @notice Add or remove an operator
    @param _operator Operator
    @param _flag True: operator, False: not operator
    @dev Can only be called by management
    """
    assert msg.sender == self.management
    assert _operator != empty(address)
    self.operators[_operator] = _flag
    log SetOperator(_operator, _flag)

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
