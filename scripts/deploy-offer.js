const hre = require("hardhat");

async function main() {
  const { market, staker } = hre.config.networks[hre.network.name];
  const { upgrades } = hre;
  // We get the contract to deploy
  const OfferContract = await ethers.getContractFactory("OfferContract");
  const offerContract = await upgrades.deployProxy(OfferContract, [market, staker]);

  //testnet 

  await offerContract.deployed();
  console.log("offerContract deployed to:", offerContract.address); 
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
