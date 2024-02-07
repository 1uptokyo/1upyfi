def test_collector(project, deployer):
    token = project.MockToken.deploy(sender=deployer)
    collector = project.RewardCollector.deploy(token, sender=deployer)
    for i in range(4):
        assert collector.fee(i) == 0
        v = 10_000
        collector.set_fee(i, v, sender=deployer)
        assert collector.fee(i) == v
