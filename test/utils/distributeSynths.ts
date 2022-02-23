import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Contract } from "ethers";

export async function distributeSynths(users: SignerWithAddress[], synths: Contract[], amounts: BigNumber[]) {
    synths.forEach((synth, index) => {
        users.forEach(async user => {
            const tx = await synth.mint(user.address, amounts[index]);
            await tx.wait();
        });
    });
}