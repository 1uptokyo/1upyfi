from ape import project

UNIT = 10**18
MAX_VALUE = 2**256 - 1
WEEK = 7 * 24 * 60 * 60
ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

YFI = '0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e'
VEYFI = '0x90c1f9220d90d3966FbeE24045EDd73E1d588aD5'
DYFI = '0x41252E8691e964f7DE35156B68493bAb6797a275'
REDEMPTION = '0x7dC3A74F0684fc026f9163C6D5c3C99fda2cf60a'
YCHAD = '0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52'

def _blueprint(contract):
    initcode = contract.contract_type.deployment_bytecode.bytecode
    assert isinstance(initcode, str)
    # https://eips.ethereum.org/EIPS/eip-5202
    initcode = bytes.fromhex(initcode.removeprefix('0x'))
    initcode = b"\xFE\x71\x00" + initcode
    len_bytes = len(initcode).to_bytes(2, "big")
    initcode = b"\x61" + len_bytes + b"\x3d\x81\x60\x0a\x3d\x39\xf3" + initcode
    return initcode

def _deploy_blueprint(contract, account, **kw):
    initcode = _blueprint(contract)
    tx = project.provider.network.ecosystem.create_transaction(
        chain_id=project.provider.chain_id,
        data=initcode,
        gas_limit=10_000_000,
        **kw
    )
    receipt = account.call(tx)
    return receipt.contract_address
