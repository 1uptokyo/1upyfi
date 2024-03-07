## 1UP specs

1UP is a liquid locker and reward booster for veYFI. The protocol lock is tokenized in the form of upYFI. Each Yearn veYFI gauge (yGauge) has a corresponding 1UP gauge that utilizes the boost from the protocol's veYFI position to enhance dYFI rewards. Rewards can be claimed as naked dYFI or can be redeemed and deposited into the protocol to receive upYFI. upYFI can be staked to receive staking rewards as well as voting power.

### Proxy
- Holder of the protocol veYFI position and all yGauge tokens
- Has set of operators
- Operators are able to call arbitary contracts through the proxy
- Operators are able to set and unset EIP-1271 signed messages
- Management can add and remove operators
- Any YFI and dYFI in the proxy is assumed to be pending staking rewards

### LiquidLocker
- Tokenization of the proxy's veYFI position
- Implementes ERC20: upYFI
- The contract is a proxy operator
- upYFI is minted in a 69420:1 ratio with the proxy's locked YFI in veYFI
- Has a function which accepts YFI deposits, adds it to the lock and mints an appropriate amount of upYFI
- Has a function which mints upYFI for any locked YFI in excess of the last known lock amount
- Has permissionless function to extend the proxy veYFI lock to 500 weeks
- Requires YFI allowance on the proxy for the voting escrow (veYFI)

### Registry
- Maintains the official mapping between yGauges and 1UP gauges
- Each yGauge has at most one 1UP gauge associated with it
- The registry is a proxy operator
- The registrar has the ability to register gauges
- On registration the gauge is approved to transfer yGauge tokens out of the proxy
- On registration the gauge is configured as reward recipient in the yGauge
- Management has the ability to deregister gauges
- Management can set the registrar

### Factory
- Allows permissionless deployment of gauges for yGauges in the [yearn registry](https://github.com/yearn/veYFI/blob/governance/contracts/governance/GaugeRegistry.vy)
- Will be set as registrar once yearn deploys its registry
- Uses EIP-5202 blueprints for the gauges
- Management can set the gauge blueprint address

### Gauge
- Implements ERC20
- Implements ERC4626 with a yGauge token as underlying asset
- Is always 1:1 with underlying
- On deployment approves reward contract to transfer all of its reward tokens (dYFI)
- Does not store balances directly, instead all balance changes are reported to the gauge rewards contract, along with all the pending rewards
- The gauge is the reward recipient for the yGauge in the proxy, as set by the registry
- Before a deposit or withdrawal the rewards are claimed from the yGauge
- On deposit the yGauge tokens are transferred directly from the caller to the proxy
- On withdrawal the yGauge tokens are transferred from the proxy to the recipient (requires prior approval, set by registry)

### GaugeRewards
- Tracks user balances for all gauges
- Tracks user pending dYFI rewards
- Tracks dYFI reward integral for all gauges and for all users for each gauge
- The reward integral is defined as the amount of total dYFI rewards per gauge token
- On gauge deposit/withdraw/transfer/transferFrom, they report the balance changes and optionally pending rewards to this contract
- If a balance change report includes pending rewards they are transferred from the gauge and the overall reward integral is updated first
- Before a balance change is applied the user's pending rewards are updated by syncing their reward integral with the overall integral
- If a deposit is reported, the contract checks the registry to verify the gauge is registered
- Anyone can harvest rewards from the gauges, which transfers them from the gauge to this contract and updates its integral
- Harvesting has an optional fee as a percentage of the harvested rewards, which is subtracted from each of the gauge rewards. The fee is paid out to the harvester
- Users can claim their rewards in three different ways:
    - As reward token (dYFI)
    - Using redeemer, without sending ETH
    - Using redeemer, with sending ETH
- Each of the reward claim methods optionally has their own fees associated with it
- Management can set the redeemer contract
- If the redeemer contract is changed, the dYFI allowance of the previous one is revoked and an allowance to the new contract is given (if applicable)
- Contract has a permissionless fee claim function which transfers the accrued fees to the treasury
- Management can set the harvest and claim fees
- Management can set the treasury address

### Staking

### StakingRewards

### BasicRedeemer
- Redeems dYFI for YFI and deposit into upYFI
- Contract used in `GaugeRewards` and `StakingRewards` as redeemer at launch
- Redeeming dYFI into YFI has an ETH cost associated with it (see [here](https://etherscan.io/address/0x7dc3a74f0684fc026f9163c6d5c3c99fda2cf60a))
- If during the redeem call ETH is supplied, it is used to cover the redemption cost
- If during the redeem call no ETH is supplied, part of the dYFI rewards are sold in the curve dYFI/ETH pool. The proceeds are then used to cover the redemption cost
- The redemeed YFI is deposited into the 1UP liquid locker and upYFI is minted to the user
- Contract has a permissionless function to send excess ETH (built up due to small price changes during redemption) to the treasury
- Management can set the treasury address
- Management can set the Yearn dYFI redemption contract. During this call the dYFI allowance to the previous contract is revoked and the allowance to the new one is set, if applicable
- Management can set the Curve dYFI/ETH pool contract. During this call the dYFI allowance to the previous contract is revoked and the allowance to the new one is set, if applicable
