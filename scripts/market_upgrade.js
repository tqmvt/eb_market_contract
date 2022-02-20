
async function main() {
    const deployer = await ethers.getSigner();
    console.log(`deployer address: ${deployer.address}`);
    const contractFactory = await ethers.getContractFactory("Marketplace");
    const market = hre.config.networks[hre.network.name].market;


    const upgrade = await upgrades.upgradeProxy(market, contractFactory);
    console.log(`market upgraded to ${upgrade.address}`);

}

main();