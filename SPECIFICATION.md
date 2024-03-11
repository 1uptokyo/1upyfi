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
- Management can mark any address as disabled, making them ineligible for registration as yGauge
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
- Implements ERC20: supYFI
- Implements ERC4626 with upYFI as underlying asset
- Is always 1:1 with underlying
- Users can deposit upYFI to become eligible for YFI/dYFI rewards and voting power on Yearn governance
- Before any change in balance (due to deposit/unstake/transfer) the previous balance is reported to a rewards contract
- upYFI cannot be freely withdrawn from the staking contract, it has to be unstaked first
- Upon unstaking the supply and user's balance is reduced and the tokens are streamed out linearly over the following 7 days
- Claiming from the stream is done with the 4626 withdrawal or redemption functions
- A user that unstakes while having another unstaking stream active will have their previous one overwritten, with any unclaimed amount added to the new stream
- Stakers accrue internal voting weight over time, linearly increasing from zero to an amount equal to their balance during a period of 8 weeks. This is done by storing the effective timestamp at which the user started staking
- The internal vote weight can be calculated as `vote_weight = balance * staking_time / (8 weeks)`
- The time staked is calculated as `staking_time = min(now - start_timestamp, 8 weeks)`
- The internal vote weight is snapshotted at the start of the week and exposed as external vote weight. The external vote weight is constant throughout the week
- User has option to lock their staking balance for up to 8 weeks
- Locking will immediately add a vote weight equal to the additional vote weight the user would have at unlock time, capped to the maximum weight, i.e. `staking_time += additional_lock_duration` (capped to 8 weeks). For example, a user depositing into the staking contract and locking for 4 weeks will receive half their max voting weight straight away and a user locking for 8 weeks will receive their full voting weight
- A user with a lock cant unstake or transfer any of their staking balance until the lock expires
- A user with a lock can still add to their staking balance through depositing or transferring, but the added balance will also become locked
- The lock duration can only be reduced if the user has a zero staking balance
- Upon staking or transfering to a user their new staking time is calculated as the average between their current staking time and their lock duration, weighted by the amounts: `new_staking_time = (min(previous_staking_time, 8 weeks) * previous_balance + lock_duration * additional_balance) / new_balance`
- Upon transferring or unstaking a percentage of a users balance, their voting weight is reduced by that same percentage. For example, a user unstaking half their stake will lose half their voting weight
- Management can set the reward contract

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
