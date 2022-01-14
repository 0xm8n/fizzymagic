const {expect} = require("chai");
const {ethers} = require("hardhat");

describe("FizzyAssetToken", async () => {
    let testContract;
    let initSupply = "1000000000000000000000000000";

    const [owner,execAddr,toAddr,invidAddr] = await ethers.getSigners();
    console.log("owner: ",owner.address);

    before(async () => {
        console.log(" ");
        await network.provider.request({
            method: "hardhat_reset",
            params: [
              {
                forking: {
                  jsonRpcUrl: process.env.CHAIN_RPC_URL || `https://data-seed-prebsc-2-s3.binance.org:8545`,
                  blockNumber: 15846557,
                },
              },
            ],
        })
        const currentBlock = await network.provider.send('eth_blockNumber', []);
        console.log('current block:', currentBlock.toString(10));

        const TestContract = await ethers.getContractFactory("FizzyAssetToken");
        testContract = await TestContract.deploy("Yield CAKE Token","yCAKE",execAddr.address);
        await testContract.deployed();
        console.log('deployer address:', testContract.deployTransaction.from);
        
        snapshotId = await ethers.provider.send('evm_snapshot', []);
        console.log('snapshot id:', snapshotId);
    });

    // afterEach(async () => {
    //     let currentBlock = await network.provider.send('eth_blockNumber', []);
    //     console.log('current block before:', currentBlock);

    //     await network.provider.send('evm_revert', [snapshotId]);
    //     snapshotId = await ethers.provider.send('evm_snapshot', []);
    //     console.log('snapshot id:', snapshotId);

    //     currentBlock = await network.provider.send('eth_blockNumber', []);
    //     console.log('current block after:', currentBlock);
    // });

    it("Should return its name", async () => {
        console.log(" ");
        expect(await testContract.name()).to.equal("Yield CAKE Token");
    });

    it("Should mint failed from invalid address", async () => {
        console.log(" ");
        await expect(testContract.connect(invidAddr).mint(owner.address,initSupply))
        .to.be.revertedWith('ERC20: must have executer role to mint');

        const totalSupply = await testContract.totalSupply();
        expect(totalSupply).to.equal(0);
        console.log("totalSupply: ",totalSupply);

        const balance = await testContract.balanceOf(owner.address);
        expect(balance).to.equal(0);
        console.log("balance: ",balance);
    });
    
    it("Should mint success from executer address", async () => {
        console.log(" ");
        await testContract.connect(execAddr).mint(owner.address,initSupply);
        const totalSupply = await testContract.totalSupply();
        expect(totalSupply).to.equal(initSupply);
        console.log("totalSupply: ",totalSupply);

        const balance = await testContract.balanceOf(owner.address);
        expect(balance).to.equal(initSupply);
        console.log("balance: ",balance);
    });

    it("Should pause failed from invalid address", async () => {
        console.log(" ");
        const amount = "1000";
        const endAmount = "999999999999999999999999000";

        let balanceFrom = await testContract.balanceOf(owner.address);
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
    
    it("Should pause success from executer address", async () => {
        console.log(" ");
        const amount = "1000";

        let balanceFrom = await testContract.balanceOf(owner.address);
        console.log("balanceFrom before : ",balanceFrom);

        await testContract.connect(execAddr).pause();
        await expect(testContract.connect(owner).transfer(toAddr.address,amount))
        .to.be.reverted;
    });
})
