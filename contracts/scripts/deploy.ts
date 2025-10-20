import { network } from "hardhat";
import { parseEther, type Address } from "viem";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

// Get __dirname equivalent in ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  console.log("🚀 Deploying MultiSigTreasury to Base Sepolia Testnet...\n");

  const { viem } = await network.connect();
  const [deployer] = await viem.getWalletClients();
  const publicClient = await viem.getPublicClient();

  // Configuration for Base Sepolia
  const INITIAL_MEMBERS: readonly Address[] = [
    "0x864c0A504da4ef27EE12b8197780e7067133587b", // Replace with actual member addresses
    "0x1062A8a3745793c2b671e4600EF33F3c0d6c29ef", // Replace with actual member addresses
  ];
  
  const APPROVAL_THRESHOLD = 2n; // Number of approvals needed (BigInt)
  const INITIAL_FUNDING = parseEther("0"); // Initial ETH to fund treasury

  console.log("📍 Network Information:");
  console.log("   Chain ID:", await publicClient.getChainId());
  console.log("   Deployer:", deployer.account.address);
  
  const deployerBalance = await publicClient.getBalance({ 
    address: deployer.account.address 
  });
  console.log("   Deployer Balance:", Number(deployerBalance) / 1e18, "ETH\n");

  console.log("⚙️  Treasury Configuration:");
  console.log("   Initial Members:", INITIAL_MEMBERS.length);
  INITIAL_MEMBERS.forEach((member, index) => {
    console.log(`   ${index + 1}. ${member}`);
  });
  console.log(`   Approval Threshold: ${APPROVAL_THRESHOLD.toString()}`);
  console.log(`   Total Members (with deployer): ${INITIAL_MEMBERS.length + 1}`);
  console.log(`   Initial Funding: ${Number(INITIAL_FUNDING) / 1e18} ETH\n`);

  // Validation
  if (INITIAL_MEMBERS.length === 0) {
    throw new Error("❌ At least one member address is required");
  }

  if (APPROVAL_THRESHOLD <= 0n) {
    throw new Error("❌ Approval threshold must be greater than 0");
  }

  if (APPROVAL_THRESHOLD > BigInt(INITIAL_MEMBERS.length + 1)) {
    throw new Error(
      `❌ Threshold (${APPROVAL_THRESHOLD}) cannot exceed total members (${INITIAL_MEMBERS.length + 1})`
    );
  }

  console.log("📝 Deploying contract...");
  
  const treasury = await viem.deployContract("MultiSigTreasury", [
    INITIAL_MEMBERS,
    APPROVAL_THRESHOLD
  ], {
    value: INITIAL_FUNDING
  });

  console.log("\n✅ MultiSigTreasury deployed successfully!");
  console.log("📋 Contract Address:", treasury.address);

  // Wait for the deployment transaction to be confirmed
  console.log("\n⏳ Waiting for deployment confirmation...");
  
  // Wait for a few blocks to ensure the contract is fully deployed
  await new Promise(resolve => setTimeout(resolve, 5000));

  // Verify deployment
  console.log("\n🔍 Verifying deployment...");
  
  try {
    const memberCount = await treasury.read.memberCount();
    const approvalThreshold = await treasury.read.approvalThreshold();
    const balance = await treasury.read.getTreasuryBalance();
    const members = await treasury.read.getMembers();

    console.log("\n✅ Contract State:");
    console.log("   Member Count:", memberCount.toString());
    console.log("   Approval Threshold:", approvalThreshold.toString());
    console.log("   Treasury Balance:", Number(balance) / 1e18, "ETH");
    console.log("   All Members:");
    
    for (const member of members) {
      const isDeployer = member.toLowerCase() === deployer.account.address.toLowerCase();
      console.log(`   - ${member}${isDeployer ? " (Deployer)" : ""}`);
    }
  } catch (error) {
    console.log("\n⚠️  Note: Contract verification will be available shortly after block confirmation");
    console.log("   You can verify the contract manually on BaseScan");
  }

  console.log("\n✨ Deployment completed successfully!\n");
  console.log("📋 Summary:");
  console.log("   Contract:", treasury.address);
  console.log("   Network: Base Sepolia Testnet");
  console.log("   Explorer:", `https://sepolia.basescan.org/address/${treasury.address}`);
  
  // Create deployment summary object
  const blockNumber = await publicClient.getBlockNumber();
  const deploymentSummary = {
    network: "base-sepolia",
    chainId: await publicClient.getChainId(),
    contractAddress: treasury.address,
    deployer: deployer.account.address,
    timestamp: new Date().toISOString(),
    blockNumber: blockNumber.toString(),
    configuration: {
      initialMembers: Array.from(INITIAL_MEMBERS),
      approvalThreshold: APPROVAL_THRESHOLD.toString(),
      totalMembers: INITIAL_MEMBERS.length + 1,
      initialFunding: (Number(INITIAL_FUNDING) / 1e18).toString() + " ETH"
    },
    explorer: `https://sepolia.basescan.org/address/${treasury.address}`,
    verifyCommand: `npx hardhat verify --network base-sepolia ${treasury.address} '["${INITIAL_MEMBERS.join('","')}"]' ${APPROVAL_THRESHOLD.toString()}`
  };

  // Save deployment summary to JSON file
  const deploymentsDir = path.join(__dirname, "../deployments");
  
  // Create deployments directory if it doesn't exist
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }

  // Save with timestamp
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const filename = `base-sepolia-${timestamp}.json`;
  const filepath = path.join(deploymentsDir, filename);
  fs.writeFileSync(filepath, JSON.stringify(deploymentSummary, null, 2));

  // Also save as latest
  const latestFilepath = path.join(deploymentsDir, "base-sepolia-latest.json");
  fs.writeFileSync(latestFilepath, JSON.stringify(deploymentSummary, null, 2));

  console.log("\n📄 Deployment summary saved to:");
  console.log("   -", filepath);
  console.log("   -", latestFilepath);
  
  console.log("\n💡 Next Steps:");
  console.log("1. Verify contract on BaseScan:");
  console.log(`   npx hardhat verify --network base-sepolia ${treasury.address} '["${INITIAL_MEMBERS.join('","')}"]' ${APPROVAL_THRESHOLD.toString()}`);
  console.log("\n2. Fund the treasury:");
  console.log(`   Send ETH to: ${treasury.address}`);
  console.log("\n3. Interact with the contract:");
  console.log("   - Members can create proposals");
  console.log("   - Vote on proposals");
  console.log("   - Execute approved proposals");

  return treasury;
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Deployment failed:");
    console.error(error);
    process.exit(1);
  });