# @version 0.3.10

interface VotingEscrow:
    def modify_lock(_amount: uint256, _unlock_time: uint256): nonpayable

implements: VotingEscrow

voting_escrow: immutable(VotingEscrow)
management: public(address)
pending_management: public(address)
operators: public(HashMap[address, bool])
messages: public(HashMap[bytes32, bool])

event PendingManagement:
    management: address

event SetManagement:
    management: address

MAX_SIZE: constant(uint256) = 1024
EIP1271_MAGIC_VALUE: constant(bytes4) = 0x1626ba7e

@external
def __init__(_voting_escrow: address):
    voting_escrow = VotingEscrow(_voting_escrow)
    self.management = msg.sender
    self.operators[msg.sender] = True

@external
@view
def isValidSignature(_hash: bytes32, _signature: Bytes[128]) -> bytes4:
    assert self.messages[_hash]
    return EIP1271_MAGIC_VALUE

@external
@payable
def call(_target: address, _data: Bytes[MAX_SIZE]):
    assert self.operators[msg.sender]
    raw_call(_target, _data, value=msg.value)

@external
def modify_lock(_amount: uint256, _unlock_time: uint256):
    assert self.operators[msg.sender]
    voting_escrow.modify_lock(_amount, _unlock_time)

@external
def set_signed_message(_hash: bytes32, _signed: bool):
    assert self.operators[msg.sender]
    self.messages[_hash] = _signed

@external
def set_operator(_operator: address, _flag: bool):
    assert msg.sender == self.management
    self.operators[_operator] = _flag

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
