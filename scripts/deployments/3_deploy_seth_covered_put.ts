import { deployVault } from "../../test/utils/deployVault"

async function main() {
    const vault = await deployVault("SETH", "coveredPut");

    console.log("sETH Covered Put Deployed: ", vault.address);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
