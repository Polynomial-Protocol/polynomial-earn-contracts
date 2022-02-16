import hre from "hardhat";

import { BigNumber, Signer } from "ethers";
import { LYRA_MARKET } from "../../../constants/constants";
import { IOptionMarket__factory } from "../../../typechain";

const { ethers, network } = hre;

export async function tradeOptions(
    listingId: BigNumber | Number,
    tradeType: BigNumber | Number,
    amount: BigNumber | Number,
    signer: Signer
) {
    let networkName = network.name === "hardhat" ? "optimism" : network.name;

    const lyraMarket = new ethers.Contract(LYRA_MARKET[networkName]["SETH"], IOptionMarket__factory.abi, signer);
}