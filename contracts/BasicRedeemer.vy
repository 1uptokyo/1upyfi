# @version 0.3.10

from vyper.interfaces import ERC20

interface Redeemer:
    def redeem(_account: address, _receiver: address, _amount: uint256, _data: Bytes[256]): payable

interface VotingEscrow:
    def modify_lock(_amount: uint256, _unlock_time: uint256, _account: address): nonpayable

interface LiquidLocker:
    def mint(_receiver: address) -> uint256: nonpayable

interface YearnRedemption:
    def eth_required(amount: uint256) -> uint256: view
    def redeem(amount: uint256) -> uint256: payable

implements: Redeemer

locking_token: public(immutable(address))
voting_escrow: public(immutable(VotingEscrow))
liquid_locker: public(immutable(LiquidLocker))
discount_token: public(immutable(ERC20))
proxy: public(immutable(address))
collector: public(immutable(address))
management: public(address)
pending_management: public(address)
yearn_redemption: public(YearnRedemption)
curve_pool: public(address)

@external
def __init__(
    _locking_token: address, _voting_escrow: address, _liquid_locker: address, 
    _discount_token: address, _proxy: address, _collector: address
):
    locking_token = _locking_token
    voting_escrow = VotingEscrow(_voting_escrow)
    liquid_locker = LiquidLocker(_liquid_locker)
    discount_token = ERC20(_discount_token)
    proxy = _proxy
    collector = _collector
    self.management = msg.sender
    assert ERC20(_locking_token).approve(_voting_escrow, max_value(uint256), default_return_value=True)

@external
@payable
def redeem(_account: address, _receiver: address, _amount: uint256, _data: Bytes[256]):
    assert msg.sender == collector
    assert discount_token.transferFrom(msg.sender, self, _amount, default_return_value=True)
    if msg.value > 0:
        self._redeem_yearn(_receiver, _amount, msg.value)
    else:
        self._redeem_curve()

@internal
def _redeem_yearn(_receiver: address, _amount: uint256, _eth_amount: uint256):
    value: uint256 = self.yearn_redemption.eth_required(_amount)
    value -= value * 3 / 1000
    assert value > 0
    assert _eth_amount >= value, "slippage"
    self.yearn_redemption.redeem(_amount, value=value)
    voting_escrow.modify_lock(_amount, 0, proxy)
    assert liquid_locker.mint(_receiver) >= _amount

@internal
def _redeem_curve():
    # TODO
    pass

@external
def set_yearn_redemption(_yearn_redemption: address):
    assert msg.sender == self.management

    previous: address = self.yearn_redemption.address
    if previous != empty(address):
        # retract previous allowance
        assert discount_token.approve(previous, 0, default_return_value=True)
    if _yearn_redemption != empty(address):
        # set new allowance
        assert discount_token.approve(_yearn_redemption, max_value(uint256), default_return_value=True)

    self.yearn_redemption = YearnRedemption(_yearn_redemption)
