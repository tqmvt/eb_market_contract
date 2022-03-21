
async function main() {
    const deployer = await ethers.getSigner();
    console.log(`deployer address: ${deployer.address}`);
    const contractFactory = await ethers.getContractFactory("OfferContract");
    const offers = hre.config.networks[hre.network.name].offers;


    const upgrade = await upgrades.upgradeProxy(offers, contractFactory);
    console.log(`market upgraded to ${upgrade.address}`);

}

main();