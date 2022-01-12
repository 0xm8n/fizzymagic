const {expect} = require("chai");
const {ethers} = require("hardhat");
const { string } = require("hardhat/internal/core/params/argumentTypes");

describe("FizzyStable", async () => {
    let testContract;
    let intSupply = 1*1e27;
    let strSupply = intSupply.toLocaleString('fullwide', {useGrouping:false});

    const [owner,execAddr,toAddr,invidAddr] = await ethers.getSigners();
    console.log("owner: ",owner.address);

    before(async () => {
        const TestContract = await ethers.getContractFactory("FizzyStable");
        testContract = await TestContract.deploy("Fizzy Stable Token","FIAT",execAddr.address);
        await testContract.deployed();
        console.log('deployer address:', testContract.deployTransaction.from);
    });

    it("Should return its name", async () => {
        expect(await testContract.name()).to.equal("Fizzy Stable Token");

    });

    it("Should Mint Failed", async () => {
        await expect(testContract.connect(invidAddr).mint(owner.address,strSupply))
        .to.be.revertedWith('ERC20: must have executer role to mint');

        const totalSupply = await testContract.totalSupply();
        expect(totalSupply).to.equal(0);
        console.log("totalSupply: ",totalSupply);

        const balance = await await testContract.balanceOf(owner.address);
        expect(balance).to.equal(0);
        console.log("balance: ",balance);
    });
    
    it("Should Mint Success", async () => {
        await testContract.connect(execAddr).mint(owner.address,strSupply);
        const totalSupply = await testContract.totalSupply();
        expect(totalSupply).to.equal(strSupply);
        console.log("totalSupply: ",totalSupply);

        const balance = await await testContract.balanceOf(owner.address);
        expect(balance).to.equal(strSupply);
        console.log("balance: ",balance);
    });

    it("Should Pause Failed", async () => {
        const amount = "1000";
        const endAmount = "999999999999999999999999000";

        let balanceFrom = await await testContract.balanceOf(owner.address);
        console.log("balanceFrom before : ",balanceFrom);

        await expect(testContract.connect(invidAddr).pause())
        .to.be.reverted;

        await testContract.connect(owner).transfer(toAddr.address,amount);

        balanceFrom = await testContract.balanceOf(owner.address);
        console.log("balanceFrom after: ",balanceFrom);
        expect(balanceFrom).to.equal(endAmount);

        let balanceTo = await testContract.balanceOf(toAddr.address);
        console.log("balanceTo: ",balanceTo);
        expect(balanceTo).to.equal(amount);
    });
    
    it("Should Pause Success", async () => {
        const amount = "1000";

        let balanceFrom = await await testContract.balanceOf(owner.address);
        console.log("balanceFrom before : ",balanceFrom);

        await testContract.connect(execAddr).pause();
        await expect(testContract.connect(owner).transfer(toAddr.address,amount))
        .to.be.reverted;
    });
})
