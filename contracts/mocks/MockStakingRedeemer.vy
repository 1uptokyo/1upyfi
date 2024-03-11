# @version 0.3.10

from vyper.interfaces import ERC20

interface Redeemer:
    def redeem(_account: address, _receiver: address, _lt_amount: uint256, _dt_amount: uint256, _data: Bytes[256]) -> uint256: payable
implements: Redeemer

interface Mintable:
    def mint(_account: address, _amount: uint256): nonpayable

locking_token: immutable(ERC20)
discount_token: immutable(ERC20)
redeem_token: immutable(Mintable)

EXPECTED_DATA: constant(Bytes[4]) = b"dcba"

@external
def __init__(_locking_token: address, _discount_token: address, _redeem_token: address):
    locking_token = ERC20(_locking_token)
    discount_token = ERC20(_discount_token)
    redeem_token = Mintable(_redeem_token)

@external
@payable
def redeem(_account: address, _receiver: address, _lt_amount: uint256, _dt_amount: uint256, _data: Bytes[256]) -> uint256:
    assert _data == EXPECTED_DATA
    assert locking_token.transferFrom(msg.sender, self, _lt_amount, default_return_value=True)
    assert discount_token.transferFrom(msg.sender, self, _dt_amount, default_return_value=True)

    # formula for mint amount is chosen arbitrarily here for testing purposes
    amount: uint256 = 3 * _lt_amount + 2 * _dt_amount + msg.value
    redeem_token.mint(_receiver, amount)
    return amount
