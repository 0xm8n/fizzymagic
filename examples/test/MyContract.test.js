const {expect} = require("chai");
const {ethers} = require("hardhat");

describe("MyContract", async () => {
    let testContract;

    beforeEach(async () => {
        const TestContract = await ethers.getContractFactory("MyContract");
        myContract = await TestContract.deploy("My Contract");
        await testContract.deployed();
    });

    it("Should return its name", async () => {
        expect(await testContract.getName()).to.equal("My Contract");
    });

    it("Should change its name ehen request", async () => {
        await testContract.changeName("Another Contract");
        expect(await testContract.getName()).to.equal("Another Contract");
    });
})
