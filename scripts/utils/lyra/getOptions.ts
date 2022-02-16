import { BigNumber } from "ethers";
import hre from "hardhat";
import { LYRA_MARKET } from "../../../constants/constants";
import { IOptionMarket__factory } from "../../../typechain";

const { ethers, network } = hre;

async function main() {
    let networkName = network.name === "hardhat" ? "optimism" : network.name;

    const lyraMarket = new ethers.Contract(LYRA_MARKET[networkName]["SETH"], IOptionMarket__factory.abi, ethers.provider);

    const liveBoards = await lyraMarket.getLiveBoards();

    liveBoards.forEach(async (board: BigNumber) => {
        const boardData = await lyraMarket.optionBoards(board);
        const timestamp = parseInt(boardData.expiry.toString());
        const date = new Date(timestamp * 1000);
        
        const boardListings = await lyraMarket.getBoardListings(board);

        boardListings.forEach(async (listingId: BigNumber) => {
            const listing = await lyraMarket.optionListings(listingId);

            const strikePrice = listing.strike.div(BigNumber.from(10).pow(18));

            console.log(date.toUTCString(), strikePrice.toString(), listingId.toString());
        });
    });
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});