/* eslint-disable node/no-missing-import */
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, network } from "hardhat";
import { FizzyMagicToken } from "../typechain";
import { toWei } from "./shared/utilities";

describe("FizzyMagicToken", async () => {
  let testContract: FizzyMagicToken;
  let snapshotId: any;
  let owner: SignerWithAddress;
  let toAddr: SignerWithAddress;
  let invidAddr: SignerWithAddress;

  const initSupply = toWei(10 ** 9).toString();
  const maxSupply = toWei(15 * 10 ** 8).toString();
  const addSupply = toWei(3 * 10 ** 8).toString();
  const passSupply = toWei(13 * 10 ** 8).toString();

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
    });
    const currentBlock = await network.provider.send("eth_blockNumber", []);
    console.log("current block:", currentBlock.toString(10));

    [owner, toAddr, invidAddr] = await ethers.getSigners();
    console.log("owner: ", owner.address);

    const TestContract = await ethers.getContractFactory("FizzyMagicToken");
    testContract = await TestContract.deploy(maxSupply);
    await testContract.deployed();
    console.log("deployer address:", testContract.deployTransaction.from);

    snapshotId = await ethers.provider.send("evm_snapshot", []);
    console.log("snapshot id:", snapshotId);
  });

  // afterEach(async () => {
  //   let currentBlock = await network.provider.send("eth_blockNumber", []);
  //   console.log("current block before:", currentBlock);

  //   await network.provider.send("evm_revert", [snapshotId]);
  //   snapshotId = await ethers.provider.send("evm_snapshot", []);
  //   console.log("snapshot id:", snapshotId);

  //   currentBlock = await network.provider.send("eth_blockNumber", []);
  //   console.log("current block after:", currentBlock);
  // });

  it("Should return its name", async () => {
    console.log(" ");
    const contractName = await testContract.name();
    console.log("contract name: ", contractName);
    expect(contractName).to.equal("Fizzy Magic Token");
  });

  it("Should mint failed from invalid address", async () => {
    console.log(" ");
    await expect(testContract.connect(invidAddr).mint(owner.address, initSupply)).to.be.revertedWith("Ownable: caller is not the owner");

    const totalSupply = await testContract.totalSupply();
    expect(totalSupply).to.equal(0);
    console.log("totalSupply: ", totalSupply);

    const balance = await testContract.balanceOf(owner.address);
    expect(balance).to.equal(0);
    console.log("balance: ", balance);
  });

  it("Should mint success from owner address", async () => {
    console.log(" ");
    await testContract.connect(owner).mint(owner.address, initSupply);

    const totalSupply = await testContract.totalSupply();
    expect(totalSupply).to.equal(initSupply);
    console.log("totalSupply: ", totalSupply);

    const balance = await testContract.balanceOf(owner.address);
    expect(balance).to.equal(initSupply);
    console.log("balance: ", balance);
  });

  it("Should mint success from under max supply", async () => {
    console.log(" ");
    await testContract.connect(owner).mint(owner.address, addSupply);

    const totalSupply = await testContract.totalSupply();
    expect(totalSupply).to.equal(passSupply);
    console.log("totalSupply: ", totalSupply);

    const balance = await testContract.balanceOf(owner.address);
    expect(balance).to.equal(passSupply);
    console.log("balance: ", balance);
  });

  it("Should mint failed from over max supply", async () => {
    console.log(" ");
    await expect(testContract.connect(owner).mint(owner.address, addSupply)).to.be.revertedWith("ERC20: cap exceeded");

    const totalSupply = await testContract.totalSupply();
    expect(totalSupply).to.equal(passSupply);
    console.log("totalSupply: ", totalSupply);

    const balance = await testContract.balanceOf(owner.address);
    expect(balance).to.equal(passSupply);
    console.log("balance: ", balance);
  });

  it("Should transfer success", async () => {
    console.log(" ");
    const amount = "1000";
    const endAmount = "1299999999999999999999999000";

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

  it("Should transer failed from amount exceeded balance", async () => {
    console.log(" ");
    const amount = "2000";
    const toAmount = "1000";
    const endAmount = "1299999999999999999999999000";

    let balanceFrom = await testContract.balanceOf(owner.address);
    console.log("balanceFrom before : ", balanceFrom);

    let balanceTo = await testContract.balanceOf(toAddr.address);
    console.log("balanceTo before: ", balanceTo);

    await expect(testContract.connect(toAddr).transfer(owner.address, amount)).to.be.reverted;

    balanceFrom = await testContract.balanceOf(owner.address);
    console.log("balanceFrom after: ", balanceFrom);
    expect(balanceFrom).to.equal(endAmount);

    balanceTo = await testContract.balanceOf(toAddr.address);
    console.log("balanceTo after: ", balanceTo);
    expect(balanceTo).to.equal(toAmount);
  });
});
