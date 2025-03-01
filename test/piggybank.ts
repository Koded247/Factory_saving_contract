import { ethers } from "hardhat";
import { expect } from "chai";
import { PiggyBank, PiggyBankFactory, MyTestToken } from "../typechain-types"; // Ensure typechain is set up

describe("PiggyBank and PiggyBankFactory Tests", () => {
  let owner: any; // Use `any` temporarily or update to proper signer type
  let user: any;
  let developer: any;

  let usdt: MyTestToken;
  let usdc: MyTestToken;
  let dai: MyTestToken;
  let factory: PiggyBankFactory;
  let piggyBank: PiggyBank;

  const ONE_DAY = 24 * 60 * 60; // 1 day in seconds
  const TOKEN_AMOUNT = ethers.parseUnits("1000", 18); // 1000 tokens

  beforeEach(async () => {
    [owner, user, developer] = await ethers.getSigners();

    // Deploy test tokens
    const MyTestTokenFactory = await ethers.getContractFactory("MyTestToken");
    usdt = await MyTestTokenFactory.deploy("Tether", "USDT", ethers.parseUnits("10000", 18));
    usdc = await MyTestTokenFactory.deploy("USD Coin", "USDC", ethers.parseUnits("10000", 18));
    dai = await MyTestTokenFactory.deploy("Dai Stablecoin", "DAI", ethers.parseUnits("10000", 18));

    // Deploy the factory
    const Factory = await ethers.getContractFactory("PiggyBankFactory");
    factory = await Factory.deploy(usdt.target, usdc.target, dai.target, developer.address); // Use .target instead of .address

    // Create a piggybank via CREATE2
    const purpose = "House Savings";
    const duration = ONE_DAY;
    const salt = ethers.formatBytes32String("house123");

    const tx = await factory.createPiggyBankWithCreate2(purpose, duration, salt);
    const receipt = await tx.wait();
    const piggyBankAddr = receipt!.logs[0]!.topics[1]; // Adjust event parsing for v6 (this is a simplification)

    piggyBank = await ethers.getContractAt("PiggyBank", piggyBankAddr);
  });

  describe("PiggyBankFactory Deployment", () => {
    it("should deploy factory with correct token addresses", async () => {
      expect(await factory.USDT_ADDRESS()).to.equal(usdt.target);
      expect(await factory.USDC_ADDRESS()).to.equal(usdc.target);
      expect(await factory.DAI_ADDRESS()).to.equal(dai.target);
      expect(await factory.developer()).to.equal(developer.address);
    });

    it("should predict and deploy to the same address with CREATE2", async () => {
      const purpose = "Car Savings";
      const duration = ONE_DAY * 2;
      const salt = ethers.formatBytes32String("car456");

      const predictedAddr = await factory.predictAddress(purpose, duration, salt);
      const tx = await factory.createPiggyBankWithCreate2(purpose, duration, salt);
      const receipt = await tx.wait();
      const deployedAddr = receipt!.logs[0]!.topics[1]; // Simplified event parsing

      expect(deployedAddr.toLowerCase()).to.equal(predictedAddr.toLowerCase());
    });

    it("should track user piggybanks", async () => {
      const userPiggyBanks = await factory.getUserPiggyBanks(owner.address);
      expect(userPiggyBanks.length).to.equal(1);
      expect(userPiggyBanks[0]).to.equal(piggyBank.target);
    });
  });

  describe("PiggyBank Functionality", () => {
    beforeEach(async () => {
      // Transfer tokens to user and approve piggybank
      await usdt.transfer(user.address, TOKEN_AMOUNT);
      await usdc.transfer(user.address, TOKEN_AMOUNT);
      await dai.transfer(user.address, TOKEN_AMOUNT);

      await usdt.connect(user).approve(piggyBank.target, TOKEN_AMOUNT);
      await usdc.connect(user).approve(piggyBank.target, TOKEN_AMOUNT);
      await dai.connect(user).approve(piggyBank.target, TOKEN_AMOUNT);
    });

    it("should initialize with correct parameters", async () => {
      expect(await piggyBank.savingsPurpose()).to.equal("House Savings");
      expect(await piggyBank.duration()).to.equal(ONE_DAY);
      expect(await piggyBank.startTime()).to.be.closeTo(
        BigInt((await ethers.provider.getBlock("latest"))!.timestamp),
        BigInt(10)
      );
      expect(await piggyBank.developer()).to.equal(developer.address);
      expect(await piggyBank.USDT_ADDRESS()).to.equal(usdt.target);
    });

    it("should allow deposits of allowed tokens", async () => {
      await piggyBank.connect(user).deposit(usdt.target, TOKEN_AMOUNT);
      expect(await piggyBank.getBalance(user.address, usdt.target)).to.equal(TOKEN_AMOUNT);

      await piggyBank.connect(user).deposit(dai.target, TOKEN_AMOUNT / BigInt(2));
      expect(await piggyBank.getBalance(user.address, dai.target)).to.equal(TOKEN_AMOUNT / BigInt(2));
    });

    it("should reject deposits of non-allowed tokens", async () => {
      const randomToken = await (await ethers.getContractFactory("MyTestToken")).deploy(
        "Random",
        "RND",
        TOKEN_AMOUNT
      );

      await expect(
        piggyBank.connect(user).deposit(randomToken.target, TOKEN_AMOUNT)
      ).to.be.revertedWith("Only USDT, USDC, or DAI allowed");
    });

    it("should allow withdrawal after duration without penalty", async () => {
      await piggyBank.connect(user).deposit(usdt.target, TOKEN_AMOUNT);

      await ethers.provider.send("evm_increaseTime", [ONE_DAY + 1]);
      await ethers.provider.send("evm_mine", []);

      const userBalanceBefore = await usdt.balanceOf(user.address);
      await piggyBank.connect(user).withdraw(usdt.target, TOKEN_AMOUNT);

      expect(await usdt.balanceOf(user.address)).to.equal(userBalanceBefore + TOKEN_AMOUNT);
      expect(await piggyBank.getBalance(user.address, usdt.target)).to.equal(0);
      expect(await piggyBank.isWithdrawn()).to.be.true;
    });

    it("should apply 15% penalty for early withdrawal", async () => {
      await piggyBank.connect(user).deposit(usdt.target, TOKEN_AMOUNT);

      const userBalanceBefore = await usdt.balanceOf(user.address);
      const devBalanceBefore = await usdt.balanceOf(developer.address);

      await piggyBank.connect(user).withdraw(usdt.target, TOKEN_AMOUNT);

      const penalty = (TOKEN_AMOUNT * BigInt(15)) / BigInt(100);
      const amountReceived = TOKEN_AMOUNT - penalty;

      expect(await usdt.balanceOf(user.address)).to.equal(userBalanceBefore + amountReceived);
      expect(await usdt.balanceOf(developer.address)).to.equal(devBalanceBefore + penalty);
      expect(await piggyBank.isWithdrawn()).to.be.true;
    });

    it("should reject deposits after withdrawal", async () => {
      await piggyBank.connect(user).deposit(usdt.target, TOKEN_AMOUNT);
      await ethers.provider.send("evm_increaseTime", [ONE_DAY + 1]);
      await ethers.provider.send("evm_mine", []);
      await piggyBank.connect(user).withdraw(usdt.target, TOKEN_AMOUNT);

      await expect(
        piggyBank.connect(user).deposit(usdt.target, TOKEN_AMOUNT)
      ).to.be.revertedWith("PiggyBank is already withdrawn");
    });

    it("should return correct time left", async () => {
      const timeLeft = await piggyBank.timeLeft();
      expect(timeLeft).to.be.closeTo(BigInt(ONE_DAY), BigInt(10));
      await ethers.provider.send("evm_increaseTime", [ONE_DAY + 1]);
      await ethers.provider.send("evm_mine", []);
      expect(await piggyBank.timeLeft()).to.equal(0);
    });
  });
});