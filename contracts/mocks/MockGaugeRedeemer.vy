# @version 0.3.10

from vyper.interfaces import ERC20

interface Redeemer:
    def redeem(_account: address, _receiver: address, _lt_amount: uint256, _dt_amount: uint256, _data: Bytes[256]) -> uint256: payable
implements: Redeemer

interface Mintable:
    def mint(_account: address, _amount: uint256): nonpayable

reward_token: immutable(ERC20)
redeem_token: immutable(Mintable)

EXPECTED_DATA: constant(Bytes[4]) = b"abcd"

@external
def __init__(_reward_token: address, _redeem_token: address):
    reward_token = ERC20(_reward_token)
    redeem_token = Mintable(_redeem_token)

@external
@payable
def redeem(_account: address, _receiver: address, _lt_amount: uint256, _dt_amount: uint256, _data: Bytes[256]) -> uint256:
    assert _lt_amount == 0
    assert _data == EXPECTED_DATA
    assert reward_token.transferFrom(msg.sender, self, _dt_amount, default_return_value=True)

    # formula for mint amount is chosen arbitrarily here for testing purposes
    amount: uint256 = 2 * _dt_amount + msg.value
    redeem_token.mint(_receiver, amount)
    return amount
