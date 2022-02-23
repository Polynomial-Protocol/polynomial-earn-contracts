import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract } from "ethers";
import { ethers } from "hardhat";

export async function batchApprove(users: SignerWithAddress[], token: Contract, target: Contract) {
    const MAX_UINT = ethers.BigNumber.from(2).pow(256).sub(1);
    users.forEach(async user => {
        const tx = await token.connect(user).approve(target.address, MAX_UINT);
        await tx.wait();
    });
}
