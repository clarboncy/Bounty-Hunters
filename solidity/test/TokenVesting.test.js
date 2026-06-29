const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("TokenVesting", function () {
  let TokenVesting, vesting, Token, token, owner, beneficiary;
  const TOTAL = ethers.parseEther("1000000000"); // 1 billion tokens
  const DURATION = 365 * 24 * 3600; // 1 year
  const CLIFF = 90 * 24 * 3600; // 90 days

  beforeEach(async function () {
    [owner, beneficiary] = await ethers.getSigners();
    Token = await ethers.getContractFactory("MockERC20");
    token = await Token.deploy("Vest Token", "VST", TOTAL);
    await token.waitForDeployment();

    const start = (await time.latest()) + 100;
    TokenVesting = await ethers.getContractFactory("TokenVesting");
    vesting = await TokenVesting.deploy(
      await token.getAddress(),
      beneficiary.address,
      TOTAL,
      start,
      CLIFF,
      DURATION
    );
    await vesting.waitForDeployment();

    await token.mint(await vesting.getAddress(), TOTAL);
  });

  describe("Overflow prevention", function () {
    it("should not overflow for 1 billion tokens with 18 decimals", async function () {
      const start = (await time.latest()) + 100;
      await time.increaseTo(start + 180 * 24 * 3600);
      const vested = await vesting.vestedAmount();
      expect(vested).to.be.gt(0);
      expect(vested).to.be.lte(TOTAL);
    });
  });

  describe("Cliff period revocation", function () {
    it("should return all tokens to owner during cliff", async function () {
      const start = (await time.latest()) + 100;
      await time.increaseTo(start + 30 * 24 * 3600);
      const vested = await vesting.vestedAmount();
      expect(vested).to.equal(0);

      await expect(vesting.revoke())
        .to.emit(vesting, "VestingRevoked")
        .withArgs(beneficiary.address, TOTAL);

      expect(await token.balanceOf(owner.address)).to.equal(TOTAL);
    });
  });

  describe("Post-cliff revocation", function () {
    it("should return only unvested tokens after partial vesting", async function () {
      const start = (await time.latest()) + 100;
      await time.increaseTo(start + 180 * 24 * 3600);
      const vested = await vesting.vestedAmount();
      expect(vested).to.be.gt(0);

      await vesting.revoke();
      expect(await token.balanceOf(beneficiary.address)).to.equal(vested);
      expect(await token.balanceOf(owner.address)).to.equal(TOTAL - vested);
    });
  });

  describe("Full vesting", function () {
    it("should vest all tokens at end of period", async function () {
      const start = (await time.latest()) + 100;
      await time.increaseTo(start + DURATION + 1);
      const vested = await vesting.vestedAmount();
      expect(vested).to.equal(TOTAL);
    });
  });

  describe("Remainder accuracy", function () {
    it("should not lose tokens due to truncation", async function () {
      const start = (await time.latest()) + 100;
      await time.increaseTo(start + DURATION);
      const vested = await vesting.vestedAmount();
      expect(vested).to.equal(TOTAL);
    });
  });
});
