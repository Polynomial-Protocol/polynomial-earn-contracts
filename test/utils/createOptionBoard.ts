import { BigNumber } from "ethers";
import { MockOptionMarket } from "../../typechain";

export async function createOptionBoard(optionMarket: MockOptionMarket, expiry: BigNumber, baseIv: BigNumber, strikes: BigNumber[], skews: BigNumber[]) {
    const tx = await optionMarket.createOptionBoard(expiry, baseIv, strikes, skews);
    await tx.wait();    
}
