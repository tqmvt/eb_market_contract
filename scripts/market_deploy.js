
async function main() {
    const deployer = await ethers.getSigner();
    console.log(`deployer address: ${deployer.address}`);
    const contractFactory = await ethers.getContractFactory("contracts/Marketplace.sol:Marketplace");
    const memberships = "0x3F1590A5984C89e6d5831bFB76788F3517Cdf034";
    const admin = "0x454cfAa623A629CC0b4017aEb85d54C42e91479d";

    const market = await upgrades.deployProxy(contractFactory, [memberships], {kind: 'uups'});
    console.log(`market deployed to ${market.address}`);

    await market.grantRole(await market.DEFAULT_ADMIN_ROLE(), admin);
    await market.grantRole(await market.UPGRADER_ROLE(), admin);
    await market.grantRole(await market.STAFF_ROLE(), admin);
    await market.revokeRole(await market.DEFAULT_ADMIN_ROLE(), deployer.address);
    // await market.revokeRole(await market.UPGRADER_ROLE(), deployer.address);
    console.log('permissions set');
}

main();