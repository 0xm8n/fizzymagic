const {expect} = require("chai");
const {ethers} = require("hardhat");

describe("MyContract", async () => {
    let myContract;

    beforeEach(async () => {
        const MyContract = await ethers.getContractFactory("MyContract");
        myContract = await MyContract.deploy("My Contract");
        await myContract.deployed();
    });

    it("Should return its name", async () => {
        expect(await myContract.getName()).to.equal("My Contract");
    });

    it("Should change its name ehen request", async () => {
        await myContract.changeName("Another Contract");
        expect(await myContract.getName()).to.equal("Another Contract");
    });
})
