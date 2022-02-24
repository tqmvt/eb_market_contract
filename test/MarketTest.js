
const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");

describe("Marketplace", async() => {

    const FOUNDER = 1;
    const VIPID = 2;
    const VVIPID =3;
    const empty = ethers.utils.formatBytes32String("");

    let deployer, admin, bob, alice, cs, dan, ed;

    let membershipFactory;
    let marketFactory;
    let nftFactory;
    let stakingFactory;
    
    let memberships;
    let market;
    let nftContract;
    let nftWithRoyalties;
    let membershipStaker
    

    before(async() => {
        [deployer, admin, staff, bob, alice, cs, dan, ed, ipHolder] = await ethers.getSigners();
        membershipFactory = await ethers.getContractFactory("EbisusBayMembership");
        stakingFactory = await ethers.getContractFactory("MembershipStaker")
        // poolFactory = await ethers.getContractFactory("RewardsPool");
        // escrowFactory = await ethers.getContractFactory("MarketEscrow");
        marketFactory = await ethers.getContractFactory("Marketplace");
        nftFactory = await ethers.getContractFactory("BasicNFT");
    });

    beforeEach(async() => {
        memberships = await membershipFactory.deploy();
        await memberships.deployed();
        // staking = await stakingFactory.deploy(memberships.address);
        // await staking.deployed();

        await memberships.updatePrice(1000, 50, FOUNDER);
        await memberships.updatePrice(1000, 50, VIPID);
        await memberships.updatePrice(1000, 50, VVIPID);
        await memberships.connect(alice).mint(VIPID, 2, empty, {'value' : 2000})
        await memberships.connect(bob).mint(VIPID, 1, empty, {'value' : 1000})
        await memberships.connect(cs).mint(VIPID, 100, empty, {'value' : 100000})
        await memberships.connect(cs).mint(VVIPID, 1, empty, {'value' : 1000})
        await memberships.connect(dan).mint(FOUNDER, 1, empty, {'value' : 1000})
        // await memberships.connect(alice).setApprovalForAll(staking.address, true);
        // await memberships.connect(bob).setApprovalForAll(staking.address, true);
        // await memberships.connect(cs).setApprovalForAll(staking.address, true);

        // market = await marketFactory.deploy(memberships.address);
        market = await upgrades.deployProxy(marketFactory, [memberships.address], {
            kind : "uups"
        });
        await market.deployed();
        await market.connect(deployer).grantRole(await market.DEFAULT_ADMIN_ROLE(), admin.address);
        await market.connect(admin).revokeRole(await market.DEFAULT_ADMIN_ROLE(), deployer.address);
        await market.connect(admin).revokeRole(await market.UPGRADER_ROLE(), deployer.address);
        await market.connect(admin).grantRole(await market.UPGRADER_ROLE(), admin.address);
        await market.connect(admin).grantRole(await market.STAFF_ROLE(), staff.address);

        nftContract = await nftFactory.deploy();
        await nftContract.deployed();
        await nftContract.safeMint(alice.address);  //0 alice
        await nftContract.safeMint(alice.address);  //1 alice
        await nftContract.safeMint(bob.address);    //2 bob
        await nftContract.safeMint(cs.address);     //3 cs 
        await nftContract.safeMint(cs.address);     //4 cs 
        await nftContract.safeMint(dan.address);    //5 dan 
        await nftContract.safeMint(dan.address);    //6 dan 
        await nftContract.safeMint(dan.address);    //7 dan


        nftWithRoyalties = await nftFactory.deploy();
        await nftWithRoyalties.deployed();
        await market.connect(staff).registerRoyalty(nftWithRoyalties.address, ipHolder.address, 500);
        await nftWithRoyalties.safeMint(alice.address); //0 alice

        membershipStaker = await stakingFactory.deploy();
        await membershipStaker.deployed();
        await market.connect(admin).setMembershipStaker(membershipStaker.address);
    });

    it('should only let admin upgrade', async () => {
        let v2 = await ethers.getContractFactory("MarketplaceV2");
        await expect(upgrades.upgradeProxy(market.address, v2)).to.be.reverted;
        v2 = await ethers.getContractFactory("MarketplaceV2", admin);
        const upgrade = await upgrades.upgradeProxy(market.address, v2);
        await expect(await upgrade.name()).to.eq("v2");
    })

    it('should tell me bytestrings', async () => {
        const a = await market.DEFAULT_ADMIN_ROLE();
        const s = await market.STAFF_ROLE();
        const u = await market.UPGRADER_ROLE();
        // console.log(`admin: ${admin}  format: ${ethers.utils.formatBytes32String(admin)}`)
        // console.log(`staff: ${staff}  format: ${ethers.utils.formatBytes32String(staff)}`)
        // console.log(`admin: ${upgrader}  format: ${ethers.utils.formatBytes32String(upgrader)}`)
        console.log(`admin: ${a}  `)
        console.log(`staff: ${s}  `)
        console.log(`admin: ${u}  `)
        console.log(`admin: ${'0x189ab7a9244df0848122154315af71fe140f3db0fe014031783b0946b8c9d2e3'}`)

        let test = await market.hasRole('0x189ab7a9244df0848122154315af71fe140f3db0fe014031783b0946b8c9d2e3', admin.address);
        console.log('.....')
        console.log(test)
    });

    it('should return paged items', async () => {
        await makeListing(alice, 0);
        let page;
        try{
            page = await market.pagedActive(1,2);
        }catch(error){
            console.log(error);
        }
        await makeListing(alice, 1);
        page = await market.pagedActive(1,2);
    });

    it('should report the total active listings', async () => {
        await nftContract.connect(alice).setApprovalForAll(market.address, true);
        await makeListing(alice, 0);
        await nftContract.connect(bob).setApprovalForAll(market.address, true);
        await makeListing(bob, 2)

        await expect(await market.totalActive()).to.eq(BigNumber.from(2));
    });

    it('should report the total completed listings', async() => {
        await nftContract.connect(alice).setApprovalForAll(market.address, true);
        await expect(makeListing(alice, 0))
            .to.emit(market, "Listed").withArgs(BigNumber.from(0));
        await expect(market.connect(bob).makePurchase(0, {'value' : 10000}))
            .to.emit(market, "Sold").withArgs(BigNumber.from(0));


        await expect(await market.totalActive()).to.eq(BigNumber.from(0));
        await expect(await market.totalComplete()).to.eq(BigNumber.from(1));
    });


    it('should reject short payment', async () => {
        await makeListing(alice, 0)
        await expect(market.connect(bob).makePurchase(0, {'value' : 9999}))
            .to.revertedWith('not enough funds');
    });

    it('should distribute payment on sale', async() => {
        await makeListing(alice, 0)
        await market.connect(bob).makePurchase(0, {'value' : 10000})
        await expect(await market.payments(alice.address)).to.eq(9850)
        await expect(await ethers.provider.getBalance(market.address)).to.eq(75);
        await expect(await ethers.provider.getBalance(membershipStaker.address)).to.eq(75);
    });

    it('should distribute roylties on royalty sale', async() => {
        await makeListingWithRoyalty(alice, 0);
        await market.connect(bob).makePurchase(0, {'value' : 10000})
        await expect(await market.payments(alice.address)).to.eq(9350)
        await expect(await market.payments(ipHolder.address)).to.eq(500)
        await expect(await ethers.provider.getBalance(market.address)).to.eq(75);
        await expect(await ethers.provider.getBalance(membershipStaker.address)).to.eq(75);
    });

    it('should transfer nft on sale', async () => {
        await makeListing(alice, 0)
        await expect(await nftContract.ownerOf(0)).to.equal(alice.address);
        await market.connect(bob).makePurchase(0, {'value' : 10000})
        await expect(await nftContract.ownerOf(0)).to.equal(bob.address);
    });

    it('should report correct fee for user', async() => {
        await expect(await market.fee(alice.address)).to.eq(150);
        await expect(await market.fee(cs.address)).to.eq(0);
        await expect(await market.fee(dan.address)).to.eq(300);
        await expect(await market.fee(ed.address)).to.eq(500);
    });

    it('should adjust fees', async() => {
        await expect(market.connect(alice).updateFees(100, 200)).to.be.reverted;
        await market.connect(admin).updateFees(400, 200, 100);
        await expect(await market.fee(alice.address)).to.eq(100);
        await expect(await market.fee(cs.address)).to.eq(0);
        await expect(await market.fee(dan.address)).to.eq(200);
        await expect(await market.fee(ed.address)).to.eq(400);
    });

    it('should pay me :) ', async () => {
        await makeListing(alice, 0)
        await market.connect(cs).makePurchase(0, {'value' : 10000})
        await expect(market.connect(staff).withdraw()).to.be.reverted;
        await expect(await market.connect(admin).withdraw()).to.changeEtherBalance(admin, 75);
    });

    it('should cancel listing by owner', async() => {
        await makeListing(alice, 0);
        await expect(market.connect(alice).cancelListing(0))
            .to.emit(market, "Cancelled").withArgs(0);

    });

    it('should not cancel other owners listing', async () => {
        await makeListing(alice, 0);
        await expect(market.connect(bob).cancelListing(0))
            .to.revertedWith('not lister');
    });

    it('should list and sell 1155', async() => {
        await memberships.connect(cs).setApprovalForAll(market.address, true);
        await market.connect(cs).makeListing(memberships.address, 2, 10000);
        await expect(await memberships.balanceOf(cs.address, 2)).to.eq(100);
        await expect(await memberships.balanceOf(dan.address, 2)).to.eq(0);
        await market.connect(dan).makePurchase(0, {'value' : 10000});
        await expect(await memberships.balanceOf(cs.address, 2)).to.eq(99);
        await expect(await memberships.balanceOf(dan.address, 2)).to.eq(1);
    });

    async function makeListing(lister, id){
        await nftContract.connect(lister).setApprovalForAll(market.address, true);
        return await market.connect(lister).makeListing(nftContract.address, id, 10000);
    }

    async function makeListingWithRoyalty(lister, id){
        await nftWithRoyalties.connect(lister).setApprovalForAll(market.address, true);
        return await market.connect(lister).makeListing(nftWithRoyalties.address, id, 10000);
    }
})