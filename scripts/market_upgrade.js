
async function main() {
    const deployer = await ethers.getSigner();
    console.log(`deployer address: ${deployer.address}`);
    const contractFactory = await ethers.getContractFactory("Marketplace");
    const market = "0x15876C450638158F48392F01dE2CEa51eccc7840";


    const upgrade = await upgrades.upgradeProxy(market, contractFactory);
    console.log(`market upgraded to ${upgrade.address}`);

}

main();