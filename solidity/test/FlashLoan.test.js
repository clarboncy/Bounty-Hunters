const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("FlashLoan", function () {
  let FlashLoan, flashLoan, Token, token, owner, borrower, attacker;

  beforeEach(async function () {
    [owner, borrower, attacker] = await ethers.getSigners();
    Token = await ethers.getContractFactory("MockERC20");
    token = await Token.deploy("Test Token", "TST", ethers.parseEther("1000000"));
    await token.waitForDeployment();

    FlashLoan = await ethers.getContractFactory("FlashLoan");
    flashLoan = await FlashLoan.deploy(await token.getAddress(), 30); // 0.3% fee
    await flashLoan.waitForDeployment();

    // Fund the pool
    await token.mint(await flashLoan.getAddress(), ethers.parseEther("10000"));
    await flashLoan.depositToPool(ethers.parseEther("10000"));
  });

  describe("Minimum fee", function () {
    it("should charge minimum fee of 1 token for small loans", async function () {
      const FlashBorrower = await ethers.getContractFactory("MockFlashBorrower");
      const flashBorrower = await FlashBorrower.deploy(await flashLoan.getAddress());
      await flashBorrower.waitForDeployment();

      // Mint tokens to borrower for repayment
      await token.mint(await flashBorrower.getAddress(), 10);

      // Loan 100 tokens — fee would be 100*30/10000 = 0 (truncates)
      // With fix, minimum fee should be 1
      await expect(
        flashBorrower.connect(borrower).executeFlashLoan(
          await token.getAddress(),
          100,
          "0x"
        )
      ).to.not.be.reverted;

      // Check that fee was charged (at least 1)
      expect(await flashLoan.totalFees()).to.be.gte(1);
    });
  });

  describe("Max loan cap", function () {
    it("should reject loans exceeding 50% of pool balance", async function () {
      const FlashBorrower = await ethers.getContractFactory("MockFlashBorrower");
      const flashBorrower = await FlashBorrower.deploy(await flashLoan.getAddress());
      await flashBorrower.waitForDeployment();

      // Pool has 10000 tokens, max loan = 5000
      await expect(
        flashBorrower.connect(borrower).executeFlashLoan(
          await token.getAddress(),
          ethers.parseEther("5001"),
          "0x"
        )
      ).to.be.revertedWith("Exceeds max loan amount");
    });
  });

  describe("Emergency pause", function () {
    it("should disable flash loans when paused", async function () {
      await flashLoan.setPaused(true);
      const FlashBorrower = await ethers.getContractFactory("MockFlashBorrower");
      const flashBorrower = await FlashBorrower.deploy(await flashLoan.getAddress());
      await flashBorrower.waitForDeployment();

      await expect(
        flashBorrower.connect(borrower).executeFlashLoan(
          await token.getAddress(),
          ethers.parseEther("100"),
          "0x"
        )
      ).to.be.revertedWith("Paused");
    });

    it("should re-enable flash loans when unpaused", async function () {
      await flashLoan.setPaused(true);
      await flashLoan.setPaused(false);
      expect(await flashLoan.paused()).to.be.false;
    });
  });

  describe("Internal accounting", function () {
    it("should track pool balance internally", async function () {
      expect(await flashLoan.getPoolBalance()).to.equal(ethers.parseEther("10000"));
    });
  });
});
