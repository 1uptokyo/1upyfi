# @version 0.3.10

from vyper.interfaces import ERC20

interface LiquidLocker:
    def deposit(_amount: uint256): nonpayable

token: public(immutable(ERC20))
liquid_locker: public(immutable(address))
threshold: public(immutable(uint256))
deposit_deadline: public(immutable(uint256))
activate_deadline: public(immutable(uint256))
owner: public(immutable(address))

activated: public(bool)
deposited: public(uint256)
deposits: public(HashMap[address, uint256])
claimed: public(HashMap[address, bool])

@external
def __init__(_token: address, _liquid_locker: address, _threshold: uint256, _deadline: uint256, _owner: address):
    token = ERC20(_token)
    liquid_locker = _liquid_locker
    threshold = _threshold
    deposit_deadline = _deadline
    activate_deadline = _deadline + 14 * 24 * 60 * 60
    owner = _owner
    assert token.approve(liquid_locker, max_value(uint256), default_return_value=True)

@external
def deposit(_amount: uint256, _account: address = msg.sender):
    assert block.timestamp < deposit_deadline, "deadline passed"
    self.deposited += _amount
    self.deposits[_account] += _amount
    assert token.transferFrom(msg.sender, self, _amount, default_return_value=True)

@external
def refund(_account: address = msg.sender):
    assert (block.timestamp >= deposit_deadline and self.deposited < threshold) or \
        (block.timestamp >= activate_deadline and not self.activated)
    amount: uint256 = self.deposits[_account]
    assert amount > 0

    self.deposited -= amount
    self.deposits[_account] = 0
    assert token.transfer(_account, amount, default_return_value=True)

@external
def claim(_account: address = msg.sender):
    assert self.activated
    assert not self.claimed[_account]
    amount: uint256 = self.deposits[_account]
    assert amount > 0

    self.claimed[_account] = True
    assert ERC20(liquid_locker).transfer(_account, amount, default_return_value=True)

@external
def activate():
    assert msg.sender == owner
    assert block.timestamp >= deposit_deadline and block.timestamp < activate_deadline
    assert self.deposited >= threshold
    assert not self.activated
    self.activated = True
    LiquidLocker(liquid_locker).deposit(self.deposited)
