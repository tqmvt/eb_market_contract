
async function main() {
    const deployer = await ethers.getSigner();
    console.log(`deployer address: ${deployer.address}`);
    const contractFactory = await ethers.getContractFactory("Marketplace");
    const memberships = "0x8d9232Ebc4f06B7b8005CCff0ca401675ceb25F5";
    const admin = process.env.LEDGER_PUBLIC;
    console.log(`admin address: ${admin}`);

    const market = await upgrades.deployProxy(contractFactory, [memberships], {kind: 'uups'});
    console.log(`market deployed to ${market.address}`);


    const adminRole = await market.DEFAULT_ADMIN_ROLE();
    const upgradeRole = await market.UPGRADER_ROLE();
    const staffRole = await market.STAFF_ROLE();
    console.log(`adminRole: ${adminRole}`);
    console.log(`upgradeRole: ${upgradeRole}`);
    console.log(`staffRole: ${staffRole}`);

    console.log("granting admin");
    await market.grantRole(adminRole, admin);
    
    console.log("granding upgrade");
    await market.grantRole(upgradeRole, admin);

    console.log("granting staff")
    await market.grantRole(staffRole, admin);
    
    // console.log("revoking admin")
    // await market.revokeRole(adminRole, deployer.address);
    // console.log("revoking upgrader");
    // await market.revokeRole(upgradeRole, deployer.address);
    console.log('permissions set');
}

main();