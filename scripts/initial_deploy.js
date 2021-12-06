const { LedgerSigner } = require("@ethersproject/hardware-wallets");  
const ethProvider = require('eth-provider') 

async function main() {
    // const owner = await ethers.getSigner();
    // console.log(owner.address);
    // const frame = ethProvider('frame');
    const contractFactory = await ethers.getContractFactory("Marketplace");
    // const tx = await contractFactory.getDeployTransaction();
    const ledger = await new LedgerSigner(contractFactory.signer.provider, "hid", "44'/60'/0'/0/0"); 
    const ledgerFactory = await contractFactory.connect(ledger);

    const test = await upgrades.deployProxy(ledgerFactory, [], {kind: 'uups'});
    console.log(`test deployed to ${test.address}`);
}

main();