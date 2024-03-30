# @version 0.3.10

"""
@title Vesting Escrow Factory
@author Curve Finance, Yearn Finance
@license MIT
@notice Stores YFI and distributes veYFI liquid locker tokens by deploying `VestingEscrowLL` contracts
"""

from vyper.interfaces import ERC20

struct Vest:
    recipient: address
    amount: uint256
    duration: uint256
    start: uint256
    cliff: uint256

num_vests: public(uint256)
pending_vests: public(HashMap[uint256, Vest])
liquid_lockers: public(HashMap[address, address]) # liquid locker token => deposit contract
operators: public(HashMap[address, HashMap[address, bool]]) # liquid locker token => operator address => approved

interface Depositor:
    def deposit(_amount: uint256) -> uint256: nonpayable

interface VestingEscrowSimple:
    def initialize(
        owner: address,
        token: address,
        recipient: address,
        amount: uint256,
        start_time: uint256,
        end_time: uint256,
        cliff_length: uint256,
        open_claim: bool,
    ) -> bool: nonpayable

event VestingEscrowCreated:
    funder: indexed(address)
    recipient: indexed(address)
    index: uint256
    amount: uint256
    vesting_start: uint256
    vesting_duration: uint256
    cliff_length: uint256

event VestingContractDeployed:
    recipient: indexed(address)
    token: indexed(address)
    index: uint256
    escrow: address
    yfi_amount: uint256
    token_amount: uint256

event LiquidLockerSet:
    liquid_locker: indexed(address)
    depositor: address

event OperatorSet:
    liquid_locker: indexed(address)
    operator: indexed(address)
    flag: bool

TARGET: public(immutable(address))
YFI: public(immutable(ERC20))
OWNER: public(immutable(address))


@external
def __init__(target: address, yfi: address, owner: address):
    """
    @notice Contract constructor
    @dev Prior to deployment you must deploy one copy of `VestingEscrowSimple` which
         is used as a library for vesting contracts deployed by this factory
    @param target `VestingEscrowSimple` contract address
    @param yfi YFI token address
    @param owner The owner of the factory that can add/remove liquid lockers and their operators
    """
    TARGET = target
    YFI = ERC20(yfi)
    OWNER = owner

@external
def create_vest(
    recipient: address, 
    amount: uint256, 
    vesting_duration: uint256, 
    vesting_start: uint256 = block.timestamp,
    cliff_length: uint256 = 0
) -> uint256:
    """
    @notice Create a new vest
    @dev Prior to deployment you must approve `amount` YFI
    @param recipient Address to vest tokens for
    @param amount Amount of tokens being vested for `recipient`
    @param vesting_duration Time period (in seconds) over which tokens are released
    @param vesting_start Epoch time when tokens begin to vest
    @param cliff_length Duration (in seconds) after which the first portion vests
    @return Vest index
    """
    assert cliff_length <= vesting_duration  # dev: incorrect vesting cliff
    assert vesting_start + vesting_duration > block.timestamp  # dev: just use a transfer, dummy
    assert vesting_duration > 0  # dev: duration must be > 0
    assert recipient not in [self, empty(address), YFI.address, OWNER] # dev: wrong recipient

    idx: uint256 = self.num_vests
    self.num_vests = idx + 1
    self.pending_vests[idx] = Vest({
        recipient: recipient,
        amount: amount,
        duration: vesting_duration,
        start: vesting_start,
        cliff: cliff_length
    })
    assert YFI.transferFrom(msg.sender, self, amount, default_return_value=True)

    log VestingEscrowCreated(
        msg.sender,
        recipient,
        idx,
        amount,
        vesting_start,
        vesting_duration,
        cliff_length
    )

    return idx

@external
def deploy_vesting_contract(
    idx: uint256,
    token: address,
    amount: uint256,
    open_claim: bool = True,
) -> (address, uint256):
    vest: Vest = self.pending_vests[idx]
    assert msg.sender == vest.recipient

    depositor: address = self.liquid_lockers[token]
    assert depositor != empty(address)

    self.pending_vests[idx].amount -= amount

    assert YFI.approve(depositor, amount, default_return_value=True)
    ll_amount: uint256 = Depositor(depositor).deposit(amount)
    assert ll_amount > 0

    escrow: address = create_minimal_proxy_to(TARGET)
    VestingEscrowSimple(escrow).initialize(
        OWNER,
        token,
        msg.sender,
        ll_amount,
        vest.start,
        vest.start + vest.duration,
        vest.cliff,
        open_claim,
    )
    assert ERC20(token).transfer(escrow, ll_amount, default_return_value=True)
    log VestingContractDeployed(
        msg.sender,
        token,
        idx,
        escrow,
        amount,
        ll_amount,
    )
    return escrow, ll_amount

@external
def set_liquid_locker(liquid_locker: address, depositor: address):
    assert msg.sender == OWNER
    assert liquid_locker != empty(address) and liquid_locker != YFI.address
    self.liquid_lockers[liquid_locker] = depositor
    log LiquidLockerSet(liquid_locker, depositor)

@external
def set_operator(liquid_locker: address, operator: address, flag: bool):
    assert msg.sender == OWNER
    assert liquid_locker != empty(address) and operator != empty(address)
    self.operators[liquid_locker][operator] = flag
    log OperatorSet(liquid_locker, operator, flag)
