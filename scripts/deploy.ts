import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with:", deployer.address);

 
  const usdtAddress = "0xdAC17F958D2ee523a2206206994597C13D831ec7"; 
  const usdcAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"; 
  const daiAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";  

  // Deploy the factory
  const PiggyBankFactory = await ethers.getContractFactory("PiggyBankFactory");
  const factory = await PiggyBankFactory.deploy(
    usdtAddress,
    usdcAddress,
    daiAddress,
    deployer.address
  );  console.log("Factory deployed at:", factory.target);

 
  console.log("Ethers version:", ethers.version); // Should print "6.x.x"

  // Create a piggybank with CREATE2
  const purpose = "House Savings";
  const duration = 30 * 24 * 60 * 60; // 30 days in seconds
  
  
  let salt;
  try {
    salt = ethers.encodeBytes32String("house123")
   
  } catch (e) {
    console.log("Falling back to Ethers v5 utils for salt");
    salt = ethers.encodeBytes32String("house123") 
  }

  const tx = await factory.createPiggyBankWithCreate2(purpose, duration, salt);
  const receipt = await tx.wait();

  
  const event = receipt!.logs
    .map((log) => {
      try {
        return factory.interface.parseLog(log);
      } catch {
        return null;
      }
    })
    .find((e) => e?.name === "PiggyBankCreated");
  const piggyBankAddr = event!.args.piggyBank;

  console.log(`PiggyBank for "${purpose}" deployed at:`, piggyBankAddr);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});