const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { BigNumber } = require("@ethersproject/bignumber");


describe("MembershipStaker", () => {

    const VIPID = 2;
    const empty = ethers.utils.formatBytes32String("");
    let owner
    let alice
    let bob
    let membershipFactory
    let memberships
    let stakerFactory
    let staker
    let fakeMemberships
    
    before(async() => {
        [owner, alice, bob, charlie, cs] = await ethers.getSigners();
        stakerFactory = await ethers.getContractFactory("MembershipStaker")
        membershipFactory = await ethers.getContractFactory("EbisusBayMembership");
    })

    beforeEach(async() => {
        memberships = await membershipFactory.deploy();
        await memberships.deployed();
        await memberships.updatePrice(1000, 50, VIPID);
        await memberships.connect(alice).mint(VIPID, 2, empty, {'value' : 2000})
        await memberships.connect(bob).mint(VIPID, 1, empty, {'value' : 1000})
        await memberships.connect(cs).mint(VIPID, 100, empty, {'value' : 100000})
        staker = await upgrades.deployProxy(stakerFactory, [memberships.address], {
            kind : "uups"
        });
        await staker.deployed();
    })

    it('init to zero', async() => {
        await expect(await staker.totalStaked()).to.eq(0);
    })

    it('should update report the correct number staked', async() => {
        await memberships.connect(alice).setApprovalForAll(staker.address, true);
        await expect(await memberships.balanceOf(alice.address, VIPID)).to.eq(2);

        await expect(staker.connect(alice).stake(1))
            .to.emit(staker, "MembershipStaked").withArgs(alice.address, 1);
        
        await expect(await staker.amountStaked(alice.address)).to.eq(1);
        await expect(await memberships.balanceOf(alice.address, VIPID)).to.eq(1);
        await expect(await staker.totalStaked()).to.eq(1);

        await expect(staker.connect(alice).stake(1))
            .to.emit(staker, "MembershipStaked").withArgs(alice.address, 2);

        await expect(await staker.amountStaked(alice.address)).to.eq(2);
        await expect(await memberships.balanceOf(alice.address, VIPID)).to.eq(0);
        await expect(await staker.totalStaked()).to.eq(2);
    });

    it('should not let user unstake more than staked', async () => {
        await memberships.connect(bob).setApprovalForAll(staker.address, true);
        await expect(await memberships.balanceOf(bob.address, VIPID)).to.eq(1);
        await staker.connect(bob).stake(1);
        await expect(staker.connect(bob).unstake(2))
            .to.revertedWith('invalid amount');
       await expect(staker.connect(bob).unstake(1))
            .to.emit(staker, "MembershipUnstaked").withArgs(bob.address, 0);     
    });

    it('should report correct amount unstaked', async () => {
        await memberships.connect(alice).setApprovalForAll(staker.address, true);
        await expect(await memberships.balanceOf(alice.address, VIPID)).to.eq(2);
        await staker.connect(alice).stake(2)
        await expect(await staker.totalStaked()).to.eq(2);
        await expect(staker.connect(alice).unstake(1))
            .to.emit(staker, "MembershipUnstaked").withArgs(alice.address, 1);
        await expect(await memberships.balanceOf(alice.address, VIPID)).to.eq(1);
        await expect(await staker.amountStaked(alice.address)).to.eq(1);
        await expect(await staker.totalStaked()).to.eq(1);
    });

    it('should reject batches', async() => {
        await expect(staker.onERC1155BatchReceived(staker.address, alice.address,[VIPID],[1], empty))
            .to.revertedWith('batches not accepted');
    });  

    it('should reject invalid opperator', async() => {
        await expect(staker.onERC1155Received(alice.address, alice.address, VIPID, 1, empty))
            .to.revertedWith('invalid operator');
    });

    it('should return all stakers and amounts', async() => {
        await memberships.connect(alice).setApprovalForAll(staker.address, true);
        await memberships.connect(bob).setApprovalForAll(staker.address, true);
        await memberships.connect(cs).setApprovalForAll(staker.address, true);
        await staker.connect(alice).stake(2);
        await staker.connect(bob).stake(1);
        await staker.connect(cs).stake(10);
        const beforeUnstake = [
            [
                alice.address,
                bob.address,
                cs.address
            ],
            [
                BigNumber.from(2),
                BigNumber.from(1),
                BigNumber.from(10)
            ]
        ]
    
        const result = await staker.currentStaked();

        expect(await staker.currentStaked()).to.eql(beforeUnstake);

        const afterUnstake =[
            [
                alice.address,
                cs.address
            ],
            [
                BigNumber.from(2),
                BigNumber.from(10)
            ]
        ]

        await staker.connect(bob).unstake(1);
        expect(await staker.currentStaked()).to.eql(afterUnstake);
    });

});