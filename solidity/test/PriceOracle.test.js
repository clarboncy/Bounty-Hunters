const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("PriceOracle", function () {
  let PriceOracle, oracle, MockFeed, feed, owner, fallbackFeed;

  beforeEach(async function () {
    [owner] = await ethers.getSigners();
    MockFeed = await ethers.getContractFactory("MockChainlinkFeed");
    feed = await MockFeed.deploy(8, 200000000000, true); // 8 decimals, $2000, valid
    await feed.waitForDeployment();

    PriceOracle = await ethers.getContractFactory("PriceOracle");
    oracle = await PriceOracle.deploy(await feed.getAddress());
    await oracle.waitForDeployment();
  });

  describe("Price validation", function () {
    it("should revert on zero price", async function () {
      await feed.setPrice(0);
      await expect(oracle.getLatestPrice()).to.be.revertedWith("Invalid price: zero or negative");
    });

    it("should revert on negative price", async function () {
      await feed.setPrice(-100);
      await expect(oracle.getLatestPrice()).to.be.revertedWith("Invalid price: zero or negative");
    });

    it("should revert on incomplete round", async function () {
      await feed.setRoundComplete(false);
      await expect(oracle.getLatestPrice()).to.be.revertedWith("Round not complete");
    });

    it("should revert on stale price", async function () {
      await feed.setUpdatedAt((await time.latest()) - 7200); // 2 hours stale
      await expect(oracle.getLatestPrice()).to.be.revertedWith("Price is stale");
    });

    it("should return valid price", async function () {
      const price = await oracle.getLatestPrice();
      expect(price).to.equal(200000000000);
    });
  });

  describe("Fallback oracle", function () {
    it("should use fallback when primary fails", async function () {
      fallbackFeed = await MockFeed.deploy(8, 190000000000, true);
      await fallbackFeed.waitForDeployment();
      await oracle.setFallbackFeed(await fallbackFeed.getAddress());

      // Break primary feed
      await feed.setPrice(0);

      const price = await oracle.getPriceWithFallback();
      expect(price).to.equal(190000000000);
    });

    it("should revert if no fallback and primary fails", async function () {
      await feed.setPrice(0);
      await expect(oracle.getPriceWithFallback()).to.be.revertedWith("No fallback oracle");
    });
  });
});
