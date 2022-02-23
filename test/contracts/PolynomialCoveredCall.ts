import { expect } from "chai";
import { ethers, network } from "hardhat";
import { deployTestSystem } from "../utils/deployTestSystem";
import { distributeSynths } from "../utils/distributeSynths";
import { BigNumber, Contract, Signer } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { batchApprove } from "../utils/batchApprove";

describe("PolynomialCoveredCall", () => {
    let ethVault : Contract, btcVault : Contract;
    const WAD = BigNumber.from(10).pow(18);
    let deployer : SignerWithAddress,
        user0 : SignerWithAddress,
        user1 : SignerWithAddress,
        user2 : SignerWithAddress,
        user3 : SignerWithAddress,
        user4 : SignerWithAddress,
        keeper : SignerWithAddress,
        feeRecepient : SignerWithAddress;

    before(async () => {
        [ deployer, user0, user1, user2, user3, user4, keeper, feeRecepient ] = await ethers.getSigners();
        const SYSTEM = await deployTestSystem(keeper, feeRecepient);

        ethVault = SYSTEM.ethCoveredCall;

        await distributeSynths(
            [user0, user1, user2, user3, user4],
            [SYSTEM.sETH, SYSTEM.sUSD, SYSTEM.sBTC],
            [WAD.mul(100), WAD.mul(1000000), BigNumber.from(10).pow(8).mul(10)]
        );

        await batchApprove(
            [user0, user1, user2, user3, user4],
            SYSTEM.sETH,
            ethVault
        );
    })

    describe("Round 0", () => {
        it("Should Deposit - I", async () => {
            const tx = await ethVault.connect(user0).depositForRoundZero(WAD);
            await tx.wait();

            const userInfo = await ethVault.userInfos(user0.address);
            expect(userInfo.totalShares).to.be.eq(WAD);
        })

        it("Should Deposit - II", async () => {
            const amount1 = WAD.mul(1743).div(563);
            const amount2 = WAD.mul(34).div(43);
            let tx = await ethVault.connect(user1).depositForRoundZero(amount1);
            await tx.wait();

            const userInfo1 = await ethVault.userInfos(user1.address);
            expect(userInfo1.totalShares).to.be.eq(amount1);

            tx = await ethVault.connect(user2).depositForRoundZero(amount2);
            await tx.wait();

            const userInfo2 = await ethVault.userInfos(user2.address);
            expect(userInfo2.totalShares).to.be.eq(amount2);

            tx = await ethVault.connect(user0).depositForRoundZero(WAD);
            await tx.wait();

            const userInfo = await ethVault.userInfos(user0.address);
            expect(userInfo.totalShares).to.be.eq(WAD.mul(2));
        })

        it("Should Withdraw", async () => {
            const tx = await ethVault.connect(user0).requestWithdraw(WAD);
            await tx.wait();

            const userInfo = await ethVault.userInfos(user0.address);
            expect(userInfo.totalShares).to.be.eq(WAD);
        })
    })
})