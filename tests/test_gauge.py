def test_rewards(project, deployer):
    token = project.MockToken.deploy(sender=deployer)
    rewards = project.GaugeRewards.deploy(token, sender=deployer)
    for i in range(4):
        assert rewards.fee(i) == 0
        v = 10_000
        rewards.set_fee(i, v, sender=deployer)
        assert rewards.fee(i) == v
