const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("SimpleSwap", function () {
  let SimpleSwap, swap, Token, tokenA, tokenB, owner, user;

  beforeEach(async function () {
    [owner, user] = await ethers.getSigners();
    Token = await ethers.getContractFactory("MockERC20");
    tokenA = await Token.deploy("Token A", "TKA", ethers.parseEther("1000000"));
    tokenB = await Token.deploy("Token B", "TKB", ethers.parseEther("1000000"));
    await tokenA.waitForDeployment();
    await tokenB.waitForDeployment();

    SimpleSwap = await ethers.getContractFactory("SimpleSwap");
    swap = await SimpleSwap.deploy(await tokenA.getAddress(), await tokenB.getAddress(), 30);
    await swap.waitForDeployment();

    // Add liquidity
    await tokenA.mint(await swap.getAddress(), ethers.parseEther("10000"));
    await tokenB.mint(await swap.getAddress(), ethers.parseEther("10000"));
    await swap.addLiquidity(ethers.parseEther("10000"), ethers.parseEther("10000"));

    // Wait — need to transferFrom, so approve first
  });

  describe("Slippage protection", function () {
    it("should revert if output is below minAmountOut", async function () {
      await tokenA.mint(user.address, ethers.parseEther("100"));
      await tokenA.connect(user).approve(await swap.getAddress(), ethers.parseEther("100"));

      const deadline = (await time.latest()) + 300;
      await expect(
        swap.connect(user).swap(
          await tokenA.getAddress(),
          ethers.parseEther("100"),
          ethers.parseEther("200"), // unreasonably high min
          deadline
        )
      ).to.be.revertedWith("Insufficient output amount");
    });

    it("should succeed with reasonable minAmountOut", async function () {
      await tokenA.mint(user.address, ethers.parseEther("100"));
      await tokenA.connect(user).approve(await swap.getAddress(), ethers.parseEther("100"));

      const deadline = (await time.latest()) + 300;
      await expect(
        swap.connect(user).swap(
          await tokenA.getAddress(),
          ethers.parseEther("100"),
          0,
          deadline
        )
      ).to.emit(swap, "Swap");
    });
  });

  describe("Deadline protection", function () {
    it("should revert if transaction is expired", async function () {
      await tokenA.mint(user.address, ethers.parseEther("100"));
      await tokenA.connect(user).approve(await swap.getAddress(), ethers.parseEther("100"));

      const expiredDeadline = (await time.latest()) - 1;
      await expect(
        swap.connect(user).swap(
          await tokenA.getAddress(),
          ethers.parseEther("100"),
          0,
          expiredDeadline
        )
      ).to.be.revertedWith("Transaction expired");
    });
  });
});
