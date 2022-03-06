import hre from 'hardhat';

const { ethers } = hre;

async function main() {
    const Resolver = await ethers.getContractFactory("Vaults");
    const resolver = await Resolver.deploy();
    await resolver.deployed();

    console.log("Resolver Deployed: ", resolver.address);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});