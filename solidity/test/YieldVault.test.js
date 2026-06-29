const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("YieldVault", function () {
  let YieldVault, vault, Token, token, owner, user;

  beforeEach(async function () {
    [owner, user] = await ethers.getSigners();
    Token = await ethers.getContractFactory("MockERC20");
    token = await Token.deploy("Stake Token", "STK", ethers.parseEther("1000000"));
    await token.waitForDeployment();

    YieldVault = await ethers.getContractFactory("YieldVault");
    vault = await YieldVault.deploy(await token.getAddress(), await token.getAddress());
    await vault.waitForDeployment();

    // Fund vault with reward tokens
    await token.mint(await vault.getAddress(), ethers.parseEther("100000"));
  });

  describe("Reward capping", function () {
    it("should not accrue rewards after periodFinish", async function () {
      await token.mint(user.address, ethers.parseEther("100"));
      await token.connect(user).approve(await vault.getAddress(), ethers.parseEther("100"));
      await vault.connect(user).deposit(ethers.parseEther("100"));

      // Notify reward: 1000 tokens over 100 seconds
      await vault.notifyRewardAmount(ethers.parseEther("1000"), 100);

      // Wait for period to end
      await time.increase(200);

      // Earned should be capped at total reward (1000 tokens)
      const earned = await vault.earned(user.address);
      expect(earned).to.be.lte(ethers.parseEther("1000"));
      expect(earned).to.be.gt(ethers.parseEther("999")); // close to 1000
    });

    it("should accrue rewards during active period", async function () {
      await token.mint(user.address, ethers.parseEther("100"));
      await token.connect(user).approve(await vault.getAddress(), ethers.parseEther("100"));
      await vault.connect(user).deposit(ethers.parseEther("100"));

      await vault.notifyRewardAmount(ethers.parseEther("1000"), 100);
      await time.increase(50);

      const earned = await vault.earned(user.address);
      expect(earned).to.be.gt(0);
      expect(earned).to.be.lt(ethers.parseEther("1000"));
    });
  });

  describe("Access control", function () {
    it("should revert if non-distributor calls notifyRewardAmount", async function () {
      await expect(
        vault.connect(user).notifyRewardAmount(ethers.parseEther("1000"), 100)
      ).to.be.revertedWith("Not reward distributor");
    });

    it("should revert if duration is zero", async function () {
      await expect(
        vault.notifyRewardAmount(ethers.parseEther("1000"), 0)
      ).to.be.revertedWith("Duration must be > 0");
    });

    it("should revert if reward is zero", async function () {
      await expect(
        vault.notifyRewardAmount(0, 100)
      ).to.be.revertedWith("Reward must be > 0");
    });
  });
});
