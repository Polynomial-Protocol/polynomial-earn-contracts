import { ethers, network } from 'hardhat';
import * as constants from "../../constants/constants";
import { PolynomialCoveredCall, PolynomialCoveredPut } from "../../typechain";

export async function deployVault(asset: String, vaultType: String): Promise<PolynomialCoveredCall | PolynomialCoveredPut> {
    if (vaultType == "coveredCall") {
        return deployCoveredCall(asset);
    } else {
        return deployCoveredPut(asset);
    }
}

async function deployCoveredCall(asset: String): Promise<PolynomialCoveredCall> {
    let networkName = network.name === "hardhat" ? "optimism" : network.name
    const CoveredCall = await ethers.getContractFactory("PolynomialCoveredCall");
    const polynomialCoveredCall = await CoveredCall.deploy(
        "FX " + asset + "Covered Call",
        constants.TOKEN_ADDR[networkName][asset as string],
        constants.SYNTHETIX_ADDR[networkName],
        constants.LYRA_MARKET[networkName][asset as string],
        constants.MARKET_PRICER[networkName][asset as string],
        constants.MARKET_VIEWER[networkName][asset as string],
        constants.SYNTH_KEYS[asset as string],
        constants.SYNTH_KEYS["SUSD"]
    );

    await polynomialCoveredCall.deployed();

    return polynomialCoveredCall;
}

async function deployCoveredPut(asset: String): Promise<PolynomialCoveredPut> {
    let networkName = network.name === "hardhat" ? "optimism" : network.name
    const CoveredPut = await ethers.getContractFactory("PolynomialCoveredPut");
    const polynomialCoveredPut = await CoveredPut.deploy(
        "FX " + asset + "Covered Put",
        constants.TOKEN_ADDR[networkName]["SUSD"],
        constants.LYRA_MARKET[networkName][asset as string],
        constants.MARKET_PRICER[networkName][asset as string],
        constants.MARKET_VIEWER[networkName][asset as string]
    );

    await polynomialCoveredPut.deployed();

    return polynomialCoveredPut;
}
