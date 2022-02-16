import { deployVault } from "../test/utils/deployVault"

async function main() {
    const vault = await deployVault("SETH", "coveredCall");

    console.log("sETH Covered Call Deployed: ", vault.address);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
