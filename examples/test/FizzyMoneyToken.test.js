const { expect } = require("chai");
const { ethers, network } = require("ethers");
const { toWei } = require("../../test/shared/utilities");

describe("FizzyMoneyToken", async () => {
  let testContract;
  let snapshotId;
  const initSupply = toWei(10 ** 9);

  const [owner, execAddr, toAddr, invidAddr] = await ethers.getSigners();
  console.log("owner: ", owner.address);

  before(async () => {
    console.log(" ");
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl:
              process.env.CHAIN_RPC_URL ||
              `https://data-seed-prebsc-2-s3.binance.org:8545`,
            blockNumber: 15846557,
          },
        },
      ],
    });
    const currentBlock = await network.provider.send("eth_blockNumber", []);
    console.log("current block:", currentBlock.toString(10));

    const TestContract = await ethers.getContractFactory("FizzyMoneyToken");
    testContract = await TestContract.deploy(
      "FizzyMoneyToken",
      "FZM",
      execAddr.address
    );
    await testContract.deployed();
    console.log("deployer address:", testContract.deployTransaction.from);

    snapshotId = await ethers.provider.send("evm_snapshot", []);
    console.log("snapshot id:", snapshotId);
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
    const contractName = await testContract.name();
    console.log("contract name: ", contractName);
    expect(contractName).to.equal("FizzyMoneyToken");
  });

  it("Should mint failed from invalid address", async () => {
    console.log(" ");
    await expect(
      testContract.connect(invidAddr).mint(owner.address, initSupply)
    ).to.be.revertedWith("AccessControl: caller is not the executor");

    const totalSupply = await testContract.totalSupply();
    expect(totalSupply).to.equal(0);
    console.log("totalSupply: ", totalSupply);

    const balance = await testContract.balanceOf(owner.address);
    expect(balance).to.equal(0);
    console.log("balance: ", balance);
  });

  it("Should mint success from executer address", async () => {
    console.log(" ");
    await testContract.connect(execAddr).mint(owner.address, initSupply);
    const totalSupply = await testContract.totalSupply();
    expect(totalSupply).to.equal(initSupply);
    console.log("totalSupply: ", totalSupply);

    const balance = await testContract.balanceOf(owner.address);
    expect(balance).to.equal(initSupply);
    console.log("balance: ", balance);
  });

  it("Should transfer failed from amount exceeded balance", async () => {
    console.log(" ");
    const amount = "1000";
    const endAmount = "0";

    let balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log("balanceFrom before : ", balanceFrom);

    await expect(testContract.connect(toAddr).transfer(owner.address, amount))
      .to.be.reverted;

    balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log("balanceFrom after: ", balanceFrom);
    expect(balanceFrom).to.equal(endAmount);

    const balanceTo = await testContract.balanceOf(owner.address);
    console.log("balanceTo: ", balanceTo);
    expect(balanceTo).to.equal(initSupply);
  });

  it("Should transfer success", async () => {
    console.log(" ");
    const amount = "1000";
    const endAmount = "999999999999999999999999000";

    let balanceFrom = await testContract.balanceOf(owner.address);
    console.log("balanceFrom before : ", balanceFrom);

    await testContract.connect(owner).transfer(toAddr.address, amount);

    balanceFrom = await testContract.balanceOf(owner.address);
    console.log("balanceFrom after: ", balanceFrom);
    expect(balanceFrom).to.equal(endAmount);

    const balanceTo = await testContract.balanceOf(toAddr.address);
    console.log("balanceTo: ", balanceTo);
    expect(balanceTo).to.equal(amount);
  });

  it("Should burn failed from amount exceeded balance", async () => {
    console.log(" ");
    const amount = "2000";
    const endAmount = "1000";

    let balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log("balance before : ", balanceFrom);

    await expect(testContract.connect(toAddr).burn(amount)).to.be.reverted;

    balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log("balance after: ", balanceFrom);
    expect(balanceFrom).to.equal(endAmount);
  });

  it("Should burn success", async () => {
    console.log(" ");
    const amount = "1000";
    const endAmount = "999999999999999999999998000";

    let balanceFrom = await testContract.balanceOf(owner.address);
    console.log("balance before : ", balanceFrom);

    await testContract.connect(owner).burn(amount);

    balanceFrom = await testContract.balanceOf(owner.address);
    console.log("balance after: ", balanceFrom);
    expect(balanceFrom).to.equal(endAmount);
  });

  it("Should burnFrom failed from not approve", async () => {
    console.log(" ");
    const amount = "200";
    const endAmount = "1000";

    let balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log("balance before : ", balanceFrom);

    await expect(testContract.connect(owner).burnFrom(toAddr.address, amount))
      .to.be.reverted;

    balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log("balance after: ", balanceFrom);
    expect(balanceFrom).to.equal(endAmount);
  });

  it("Should transferFrom failed from not approve", async () => {
    console.log(" ");
    const amount = "200";
    const endAmount = "1000";
    const ownerAmount = "999999999999999999999998000";

    let balanceTo = await testContract.balanceOf(owner.address);
    console.log("balanceTo before : ", balanceTo);

    let balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log("balanceFrom before : ", balanceFrom);

    await expect(
      testContract
        .connect(owner)
        .transferFrom(toAddr.address, owner.address, amount)
    ).to.be.reverted;

    balanceTo = await testContract.balanceOf(owner.address);
    console.log("balanceTo after: ", balanceTo);
    expect(balanceTo).to.equal(ownerAmount);

    balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log("balanceFrom after: ", balanceFrom);
    expect(balanceFrom).to.equal(endAmount);
  });

  it("Should burnFrom success", async () => {
    console.log(" ");
    const amount = "200";
    const endAmount = "800";

    let balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log("balance before : ", balanceFrom);

    await testContract.connect(toAddr).approve(owner.address, initSupply);
    await testContract.connect(owner).burnFrom(toAddr.address, amount);

    balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log("balance after: ", balanceFrom);
    expect(balanceFrom).to.equal(endAmount);
  });

  it("Should transferFrom Success", async () => {
    console.log(" ");
    const amount = "200";
    const endAmount = "600";
    const ownerAmount = "999999999999999999999998200";

    let balanceTo = await testContract.balanceOf(owner.address);
    console.log("balanceTo before : ", balanceTo);

    let balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log("balanceFrom before : ", balanceFrom);

    // await testContract.connect(toAddr).approve(owner.address,initSupply);
    await testContract
      .connect(owner)
      .transferFrom(toAddr.address, owner.address, amount);

    balanceTo = await testContract.balanceOf(owner.address);
    console.log("balanceTo after: ", balanceTo);
    expect(balanceTo).to.equal(ownerAmount);

    balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log("balanceFrom after: ", balanceFrom);
    expect(balanceFrom).to.equal(endAmount);
  });
});
