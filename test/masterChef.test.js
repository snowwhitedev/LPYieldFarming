const { expect, assert } = require('chai');
const { BigNumber } = require('ethers');
// const { providers } = require("ethers");
const { ethers } = require('hardhat');
const {
  getBigNumber,
  advanceBlock,
  advanceBlockTo
  // advanceTimeStamp,
} = require('../scripts/shared/utilities.js');

const SB_PER_BLOCK = getBigNumber(1, 18); // 1 SB per block

describe('SBMasterChef', function () {
  before(async function () {
    this.MasterChef = await ethers.getContractFactory('SBMasterChef');
    this.Rewarder = await ethers.getContractFactory('Rewarder');
    this.MockERC20 = await ethers.getContractFactory('MockERC20');
    this.signers = await ethers.getSigners();

    this.dev = this.signers[0];
    this.alice = this.signers[1];
    this.bob = this.signers[2];
  });

  beforeEach(async function () {
    this.sbToken = await this.MockERC20.deploy('SugarBounce', 'SB');
    this.sbWbnbLP = await this.MockERC20.deploy('SB_WBNB LP', 'SB_WBNB');

    this.masterChef = await this.MasterChef.deploy(SB_PER_BLOCK, ~~(new Date().getTime() / 1000));
    this.rewarder = await this.Rewarder.deploy(this.sbToken.address, this.masterChef.address);
    this.masterChef.setRewarder(this.rewarder.address);

    await this.sbWbnbLP.transfer(this.alice.address, getBigNumber(1000000));
    await this.sbWbnbLP.transfer(this.bob.address, getBigNumber(1000000));
  });

  describe('Test', function () {
    it('Test', function () {
      console.log('Test started');
    });
  });

  describe('PoolLength', function () {
    it('PoolLength should be increased', async function () {
      await this.masterChef.add(50 * 100, this.sbWbnbLP.address);
      expect(await this.masterChef.poolLength()).to.be.equal(1);
    });

    it('Each Pool can not be added twice', async function () {
      await this.masterChef.add(50 * 100, this.sbWbnbLP.address);
      expect(await this.masterChef.poolLength()).to.be.equal(1);

      await expect(this.masterChef.add(50 * 100, this.sbWbnbLP.address)).to.be.revertedWith(
        'SBMasterChef: Pool already exists'
      );
    });
  });

  describe('Set', function () {
    it('Should emit SetPool', async function () {
      await this.masterChef.add(50 * 100, this.sbWbnbLP.address);
      await expect(this.masterChef.set(0, 60 * 100))
        .to.emit(this.masterChef, 'LogSetPool')
        .withArgs(0, 60 * 100);
    });

    it('Should revert if invalid pool', async function () {
      await expect(this.masterChef.set(2, 60 * 100)).to.be.revertedWith('SBMasterChef: Pool does not exist');
    });
  });

  describe('Pending SB', function () {
    it('Pending SB should be equal to expected amount', async function () {
      await this.masterChef.add(50 * 100, this.sbWbnbLP.address);
      await this.sbWbnbLP.connect(this.alice).approve(this.masterChef.address, getBigNumber(1000000000000000));

      const log1 = await (
        await this.masterChef.connect(this.alice).deposit(0, getBigNumber(1000), this.alice.address)
      ).wait();
      const block1 = await ethers.provider.getBlock(log1.blockHash);

      await advanceBlock();

      const log2 = await this.masterChef.connect(this.alice).updatePool(0);
      const block2 = await ethers.provider.getBlock(log2.blockHash);

      const expectedSB = SB_PER_BLOCK.mul(block2.number - block1.number);
      const pendingSB = await this.masterChef.pendingRewards(0, this.alice.address);
      expect(expectedSB).to.be.equal(pendingSB);

      const poolInfo = await this.masterChef.poolInfo(0);
      expect(poolInfo.lastRewardBlock).to.be.equal(block2.number);
    });
  });

  describe('Deposit', function () {
    beforeEach(async function () {
      await this.masterChef.add(50 * 100, this.sbWbnbLP.address);
      await this.sbWbnbLP.approve(this.masterChef.address, getBigNumber(1000000000000000));
    });

    it('Should deposit and update pool info', async function () {});

    it('Should not allow to deposit in non-existent pool', async function () {
      await expect(this.masterChef.deposit(1001, getBigNumber(1), this.dev.address)).to.be.revertedWith(
        'SBMasterChef: Pool does not exist'
      );
    });
  });

  describe('Withdraw', function () {
    beforeEach(async function () {});

    it('Withdraw some amount and harvest rewards', async function () {
      await this.masterChef.add(50 * 100, this.sbWbnbLP.address);
      await this.sbWbnbLP.connect(this.alice).approve(this.masterChef.address, getBigNumber(1000000000000000));
      await this.sbToken.transfer(this.rewarder.address, getBigNumber(100000000));

      const depositLog = await (
        await this.masterChef.connect(this.alice).deposit(0, getBigNumber(1000), this.alice.address)
      ).wait();

      const sbBalanceBefore = await this.sbToken.balanceOf(this.alice.address);

      await advanceBlockTo(depositLog.blockNumber + 3);

      const withdrawLog = await this.masterChef.connect(this.alice).withdraw(0, getBigNumber(100));

      const expectedSB = SB_PER_BLOCK.mul(withdrawLog.blockNumber - depositLog.blockNumber); // Pending amount

      const sbBalanceAfter = await this.sbToken.balanceOf(this.alice.address);

      expect(expectedSB.add(sbBalanceBefore)).to.be.equal(sbBalanceAfter);
    });
  });

  describe('EmergencyWithdraw', function () {
    beforeEach(async function () {});

    it('EmergencyWithdraw', async function () {
      await this.masterChef.add(50 * 100, this.sbWbnbLP.address);
      await this.sbWbnbLP.connect(this.bob).approve(this.masterChef.address, getBigNumber(1000000000000000));
      await this.sbToken.transfer(this.rewarder.address, getBigNumber(100000000));

      const sbWbnbLPBalance0 = await this.sbWbnbLP.balanceOf(this.bob.address);

      await (await this.masterChef.connect(this.bob).deposit(0, getBigNumber(1000), this.bob.address)).wait();

      const userInfo0 = await this.masterChef.userInfo(0, this.bob.address);
      await (await this.masterChef.connect(this.bob).deposit(0, getBigNumber(1000), this.bob.address)).wait();

      const userInfo1 = await this.masterChef.userInfo(0, this.bob.address);

      console.log('userInfo1', userInfo1.amount.toString());

      await expect(this.masterChef.connect(this.bob).emergencyWithdraw(0, this.bob.address))
        .to.emit(this.masterChef, 'EmergencyWithdraw')
        .withArgs(this.bob.address, 0, BigNumber.from(userInfo1.amount), this.bob.address);

      const sbWbnbLPBalanceAfter = await this.sbWbnbLP.balanceOf(this.bob.address);

      expect(sbWbnbLPBalance0).to.be.equal(sbWbnbLPBalanceAfter);

      const userInfoAfter = await this.masterChef.userInfo(0, this.bob.address);
      expect(userInfoAfter.amount).to.be.equal(0);
      expect(userInfoAfter.rewardDebt).to.be.equal(0);
    });
  });
});
