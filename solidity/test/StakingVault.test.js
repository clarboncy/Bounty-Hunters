const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("StakingVault", function () {
  let StakingVault, vault, Token, token, owner, user, attacker;

  beforeEach(async function () {
    [owner, user, attacker] = await ethers.getSigners();
    Token = await ethers.getContractFactory("MockERC20");
    token = await Token.deploy("Stake Token", "STK", ethers.parseEther("1000000"));
    await token.waitForDeployment();

    StakingVault = await ethers.getContractFactory("StakingVault");
    vault = await StakingVault.deploy(await token.getAddress(), ethers.parseEther("0.001"));
    await vault.waitForDeployment();

    // Fund vault with reward tokens
    await token.mint(await vault.getAddress(), ethers.parseEther("100000"));
  });

  describe("Staking", function () {
    it("should allow staking", async function () {
      await token.mint(user.address, ethers.parseEther("100"));
      await token.connect(user).approve(await vault.getAddress(), ethers.parseEther("100"));
      await vault.connect(user).stake(ethers.parseEther("100"));
      expect(await vault.getStakedBalance(user.address)).to.equal(ethers.parseEther("100"));
    });
  });

  describe("Withdrawal — CEI pattern", function () {
    it("should update state before transfer", async function () {
      await token.mint(user.address, ethers.parseEther("100"));
      await token.connect(user).approve(await vault.getAddress(), ethers.parseEther("100"));
      await vault.connect(user).stake(ethers.parseEther("100"));

      await vault.connect(user).withdraw(ethers.parseEther("50"));
      expect(await vault.getStakedBalance(user.address)).to.equal(ethers.parseEther("50"));
    });
  });

  describe("Reentrancy protection", function () {
    it("should prevent reentrancy on withdraw", async function () {
      const Attacker = await ethers.getContractFactory("ReentrancyAttacker");
      const attackerContract = await Attacker.deploy(await vault.getAddress(), await token.getAddress());
      await attackerContract.waitForDeployment();

      await token.mint(await attackerContract.getAddress(), ethers.parseEther("100"));
      await attackerContract.stake(ethers.parseEther("100"));

      // Attempt reentrancy — should fail
      await expect(attackerContract.attack()).to.be.reverted;
    });
  });
});
