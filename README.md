## 1UP
1UP is a boost aggregator for Yearn's [veYFI](https://docs.yearn.fi/getting-started/products/veyfi) operating as a neutral public good. Written from the ground up, 1UP's immutable codebase allows YFI holders, Yearn contributors, and teams, to lock YFI into veYFI while at the same time aggregating and sharing the boost amongst one another. This is achieved without extracting value from the system, 100% of fees levied are directed back into the protocol for the sole purpose of perpetually growing its veYFI position, deepen liquidity, and grow the user base.

### Specification
The specification can be found here: [SPECIFICATION.md](./SPECIFICATION.md)

### Usage

#### Install dependencies
```sh
# Install foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup
# Install ape
pip install eth-ape
# Install required ape plugins
ape plugins install .
```

In `ape-config.yaml` of either this directory or `~/.ape`, add the following lines, where `https://RPC_URL` is replaced with the URL of your preferred RPC
```yaml
geth:
  ethereum:
    mainnet:
      uri: https://RPC_URL
```

#### Run tests
```sh
ape test
```
