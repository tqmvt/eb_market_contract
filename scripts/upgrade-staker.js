
async function main() {
    const deployer = await ethers.getSigner();
    console.log(`deployer address: ${deployer.address}`);
    const contractFactory = await ethers.getContractFactory("MembershipStakerV2");
    const staker = hre.config.networks[hre.network.name].staker;


    const upgrade = await upgrades.upgradeProxy(staker, contractFactory);
    console.log(`market upgraded to ${upgrade.address}`);

}

main();