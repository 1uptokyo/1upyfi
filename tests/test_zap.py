from ape import reverts, Contract
from pytest import fixture
from _constants import *

WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'
DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F'
YFI_LP = '0x29059568bB40344487d62f7450E78b8E6C74e0e5'

WETH_GAUGE = '0xfd14Fde2e67A6E1b2BbEDa72336Eb682e76Fd7AE'
DAI_GAUGE = '0xc3E4ae5F6894863eD62Af62e527ed61587eD58bD'
YFI_LP_GAUGE = '0x6FB0d27A572975fae301800b6cb121Cd3f3bAa11'

DAI_WHALE = '0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503'
YFI_LP_POOL = '0xC26b89A667578ec7b3f11b2F98d6Fd15C07C54ba'

@fixture
def weth():
    return Contract(WETH)

@fixture
def weth_gauge():
    return Contract(WETH_GAUGE)

@fixture
def dai():
    return Contract(DAI)

@fixture
def dai_gauge():
    return Contract(DAI_GAUGE)

@fixture
def dai_whale(accounts):
    return accounts[DAI_WHALE]

@fixture
def yfi_lp():
    return Contract(YFI_LP)

@fixture
def yfi_lp_gauge():
    return Contract(YFI_LP_GAUGE)

@fixture
def yfi_lp_pool():
    return Contract(YFI_LP_POOL)

@fixture
def zap(project, deployer, weth):
    return project.Zap.deploy(weth, sender=deployer)

def test_deposit(dai, dai_gauge, dai_whale, zap):
    amt = 1_000 * UNIT
    bal = dai.balanceOf(dai_whale)
    dai.approve(zap, amt, sender=dai_whale)

    assert dai_gauge.balanceOf(dai_whale) == 0
    shares = zap.deposit(dai_gauge, amt, sender=dai_whale).return_value
    assert shares > 0
    assert dai.balanceOf(dai_whale) == bal - amt
    assert dai_gauge.balanceOf(dai_whale) == shares

    dai_vault = Contract(dai_gauge.asset())
    assert abs(dai_vault.convertToAssets(shares)-amt) <= 2

def test_deposit_eth(alice, weth_gauge, zap):
    amt = UNIT
    assert weth_gauge.balanceOf(alice) == 0
    shares = zap.deposit_eth(weth_gauge, value=UNIT, sender=alice).return_value
    assert shares > 0
    assert weth_gauge.balanceOf(alice) == shares

    weth_vault = Contract(weth_gauge.asset())
    assert abs(weth_vault.convertToAssets(shares)-amt) <= 1

def test_deposit_legacy(alice, yfi_lp, yfi_lp_gauge, yfi_lp_pool, zap):
    amt = UNIT
    yfi_lp_pool.add_liquidity([10 * UNIT, 0], 0, True, value=10 * UNIT, sender=alice)
    bal = yfi_lp.balanceOf(alice)
    yfi_lp.approve(zap, amt, sender=alice)

    assert yfi_lp_gauge.balanceOf(alice) == 0
    shares = zap.deposit_legacy(yfi_lp_gauge, amt, sender=alice).return_value
    assert shares > 0
    assert yfi_lp.balanceOf(alice) == bal - amt
    assert yfi_lp_gauge.balanceOf(alice) == shares

def test_withdraw(dai, dai_gauge, dai_whale, zap):
    amt = 1_000 * UNIT
    dai.approve(zap, 2_000 * UNIT, sender=dai_whale)
    zap.deposit(dai_gauge, 2_000 * UNIT, sender=dai_whale)
    
    bal = dai.balanceOf(dai_whale)
    gauge_bal = dai_gauge.balanceOf(dai_whale)
    dai_gauge.approve(zap, amt, sender=dai_whale)
    assets = zap.withdraw(dai_gauge, amt, sender=dai_whale).return_value
    assert assets > amt
    assert dai_gauge.balanceOf(dai_whale) == gauge_bal - amt
    assert dai.balanceOf(dai_whale) == bal + assets

def test_withdraw_eth(alice, weth_gauge, zap):
    amt = UNIT
    zap.deposit_eth(weth_gauge, value=2 * UNIT, sender=alice)

    bal = alice.balance
    gauge_bal = weth_gauge.balanceOf(alice)
    weth_gauge.approve(zap, amt, sender=alice)
    assets = zap.withdraw_eth(weth_gauge, amt, sender=alice).return_value
    assert assets > amt
    assert weth_gauge.balanceOf(alice) == gauge_bal - amt
    assert alice.balance > bal + amt

def test_withdraw_legacy(alice, yfi_lp, yfi_lp_gauge, yfi_lp_pool, zap):
    amt = UNIT
    yfi_lp_pool.add_liquidity([10 * UNIT, 0], 0, True, value=10 * UNIT, sender=alice)
    yfi_lp.approve(zap, 2 * amt, sender=alice)
    zap.deposit_legacy(yfi_lp_gauge, 2 * amt, sender=alice)
    
    bal = yfi_lp.balanceOf(alice)
    gauge_bal = yfi_lp_gauge.balanceOf(alice)
    yfi_lp_gauge.approve(zap, amt, sender=alice)
    assets = zap.withdraw_legacy(yfi_lp_gauge, amt, sender=alice).return_value
    assert assets > amt
    assert yfi_lp_gauge.balanceOf(alice) == gauge_bal - amt
    assert yfi_lp.balanceOf(alice) == bal + assets

def test_rescue(deployer, alice, dai, dai_whale, zap):
    dai.transfer(zap, 3 * UNIT, sender=dai_whale)

    with reverts():
        zap.rescue(dai, UNIT, sender=alice)

    bal = dai.balanceOf(deployer)
    zap.rescue(dai, UNIT, sender=deployer)
    assert dai.balanceOf(zap) == 2 * UNIT
    assert dai.balanceOf(deployer) == bal + UNIT

    zap.rescue(dai, sender=deployer)
    assert dai.balanceOf(zap) == 0
    assert dai.balanceOf(deployer) == bal + 3 * UNIT

def test_management(deployer, alice, zap):
    assert zap.management() == deployer

    with reverts():
        zap.set_management(alice, sender=alice)

    zap.set_management(alice, sender=deployer)
    assert zap.management() == alice
