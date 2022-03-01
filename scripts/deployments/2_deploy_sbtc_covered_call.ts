import { deployVault } from "../../test/utils/deployVault"

async function main() {
    const vault = await deployVault("SBTC", "coveredCall");

    console.log("sBTC Covered Call Deployed: ", vault.address);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
