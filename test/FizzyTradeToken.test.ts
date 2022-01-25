import {expect} from 'chai';
import { ethers,network } from "hardhat";
import { Contract } from 'ethers';
import { toWei } from './shared/utilities';

describe('FizzyTradeToken', async () => {
  let snapshotId;
  let testContract: Contract;
  let initSupply = toWei(10 ** 9);

  const [deployer,execAddr,toAddr,invidAddr] = await ethers.getSigners();
  console.log("owner: ",deployer.address);

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

        const TestContract = await ethers.getContractFactory("FizzyTradeToken");
        testContract = await TestContract.deploy("Fizzy Trade Token","FIZT");

        await testContract.deployed();
        const cap = await testContract.maxSupply();
        console.log('deployer address:', testContract.deployTransaction.from);
        console.log('max supply:', cap);

        snapshotId = await ethers.provider.send('evm_snapshot', []);
        console.log('snapshot id:', snapshotId);
    });

//   before(async () => {
//     console.log(' ');
//     const currentBlock = await provider.send('eth_blockNumber', []);
//     console.log('current block:', currentBlock.toString(10));

//     testContract = fixture.fizzyTradeToken;
//     console.log('deployer address:', testContract.deployTransaction.from);

//     snapshotId = await provider.send('evm_snapshot', []);
//     console.log('snapshot id:', snapshotId);
//   });

  // afterEach(async () => {
  //     let currentBlock = await network.provider.send('eth_blockNumber', [])
  //     console.log('current block before:', currentBlock)

  //     await network.provider.send('evm_revert', [snapshotId])
  //     snapshotId = await ethers.provider.send('evm_snapshot', [])
  //     console.log('snapshot id:', snapshotId)

  //     currentBlock = await network.provider.send('eth_blockNumber', [])
  //     console.log('current block after:', currentBlock)
  // })

  it('Should return its name', async () => {
    console.log(' ');
    const contractName = await testContract.name();
    console.log('contract name: ', contractName);
    expect(contractName).to.equal('CAKE Trade Token');
  });

  it('Should mint failed from invalid address', async () => {
    console.log(' ');
    await expect(testContract.connect(invidAddr).mint(deployer.address, initSupply)).to.be.revertedWith(
      'AccessControl: caller is not the executor'
    );

    const totalSupply = await testContract.totalSupply();
    expect(totalSupply).to.equal(0);
    console.log('totalSupply: ', totalSupply);

    const balance = await testContract.balanceOf(deployer.address);
    expect(balance).to.equal(0);
    console.log('balance: ', balance);
  });

  it('Should mint success from executer address', async () => {
    console.log(' ');
    await testContract.connect(execAddr).mint(deployer.address, initSupply);
    const totalSupply = await testContract.totalSupply();
    expect(totalSupply).to.equal(initSupply);
    console.log('totalSupply: ', totalSupply);

    const balance = await testContract.balanceOf(deployer.address);
    expect(balance).to.equal(initSupply);
    console.log('balance: ', balance);
  });

  it('Should transfer failed from amount exceeded balance', async () => {
    console.log(' ');
    const amount = toWei(1000);
    const endAmount = toWei(0);

    let balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log('balanceFrom before : ', balanceFrom);

    await expect(testContract.connect(toAddr).transfer(deployer.address, amount)).to.be.reverted;

    balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log('balanceFrom after: ', balanceFrom);
    expect(balanceFrom).to.equal(endAmount);

    let balanceTo = await testContract.balanceOf(deployer.address);
    console.log('balanceTo: ', balanceTo);
    expect(balanceTo).to.equal(initSupply);
  });

  it('Should transfer success', async () => {
    console.log(' ');
    const amount = toWei(1000);
    const endAmount = toWei(10 ** 9 - 1000);

    let balanceFrom = await testContract.balanceOf(deployer.address);
    console.log('balanceFrom before : ', balanceFrom);

    await testContract.connect(deployer).transfer(toAddr.address, amount);

    balanceFrom = await testContract.balanceOf(deployer.address);
    console.log('balanceFrom after: ', balanceFrom);
    expect(balanceFrom).to.equal(endAmount);

    let balanceTo = await testContract.balanceOf(toAddr.address);
    console.log('balanceTo: ', balanceTo);
    expect(balanceTo).to.equal(amount);
  });

  it('Should burn failed from amount exceeded balance', async () => {
    console.log(' ');
    const amount = toWei(2000);
    const endAmount = toWei(1000);

    let balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log('balance before : ', balanceFrom);

    await expect(testContract.connect(toAddr).burn(amount)).to.be.reverted;

    balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log('balance after: ', balanceFrom);
    expect(balanceFrom).to.equal(endAmount);
  });

  it('Should burn success', async () => {
    console.log(' ');
    const amount = toWei(1000);
    const endAmount = toWei(10 ** 9 - 2000);

    let balanceFrom = await testContract.balanceOf(deployer.address);
    console.log('balance before : ', balanceFrom);

    await testContract.connect(deployer).burn(amount);

    balanceFrom = await testContract.balanceOf(deployer.address);
    console.log('balance after: ', balanceFrom);
    expect(balanceFrom).to.equal(endAmount);
  });

  it('Should burnFrom failed from not approve', async () => {
    console.log(' ');
    const amount = toWei(200);
    const endAmount = toWei(1000);

    let balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log('balance before : ', balanceFrom);

    await expect(testContract.connect(deployer).burnFrom(toAddr.address, amount)).to.be.reverted;

    balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log('balance after: ', balanceFrom);
    expect(balanceFrom).to.equal(endAmount);
  });

  it('Should transferFrom failed from not approve', async () => {
    console.log(' ');
    const amount = toWei(200);
    const endAmount = toWei(1000);
    const deployerAmount = toWei(10 ** 9 - 2000);

    let balanceTo = await testContract.balanceOf(deployer.address);
    console.log('balanceTo before : ', balanceTo);

    let balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log('balanceFrom before : ', balanceFrom);

    await expect(testContract.connect(deployer).transferFrom(toAddr.address, deployer.address, amount)).to.be.reverted;

    balanceTo = await testContract.balanceOf(deployer.address);
    console.log('balanceTo after: ', balanceTo);
    expect(balanceTo).to.equal(deployerAmount);

    balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log('balanceFrom after: ', balanceFrom);
    expect(balanceFrom).to.equal(endAmount);
  });

  it('Should burnFrom success', async () => {
    console.log(' ');
    const amount = toWei(200);
    const endAmount = toWei(800);

    let balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log('balance before : ', balanceFrom);

    await testContract.connect(toAddr).approve(deployer.address, initSupply);
    await testContract.connect(deployer).burnFrom(toAddr.address, amount);

    balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log('balance after: ', balanceFrom);
    expect(balanceFrom).to.equal(endAmount);
  });

  it('Should transferFrom Success', async () => {
    console.log(' ');
    const amount = toWei(200);
    const endAmount = toWei(600);
    const deployerAmount = toWei(10 ** 9 - 1800);

    let balanceTo = await testContract.balanceOf(deployer.address);
    console.log('balanceTo before : ', balanceTo);

    let balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log('balanceFrom before : ', balanceFrom);

    // await testContract.connect(toAddr).approve(deployer.address,initSupply)
    await testContract.connect(deployer).transferFrom(toAddr.address, deployer.address, amount);

    balanceTo = await testContract.balanceOf(deployer.address);
    console.log('balanceTo after: ', balanceTo);
    expect(balanceTo).to.equal(deployerAmount);

    balanceFrom = await testContract.balanceOf(toAddr.address);
    console.log('balanceFrom after: ', balanceFrom);
    expect(balanceFrom).to.equal(endAmount);
  });
});
