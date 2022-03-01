import { expect } from "chai";
import { ethers, network } from "hardhat";
import { deployTestSystem } from "../utils/deployTestSystem";
import { distributeSynths } from "../utils/distributeSynths";
import { BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { batchApprove } from "../utils/batchApprove";
import { VOL_ROUND_TIMESTAMPS } from "../../constants/constants";
import { createOptionBoard } from "../utils/createOptionBoard";
import { MockOptionMarket, MockOptionViewer, MockSynthetix, PolynomialShortVol } from "../../typechain";
import { toBN } from "../../scripts/utils/general/toBN";

describe("PolynomialShortVol", () => {
    let ethVault: PolynomialShortVol;
    const MAX_UINT = ethers.BigNumber.from(2).pow(256).sub(1);
    const WAD = BigNumber.from(10).pow(18);
    let deployer : SignerWithAddress,
        user0 : SignerWithAddress,
        user1 : SignerWithAddress,
        user2 : SignerWithAddress,
        user3 : SignerWithAddress,
        user4 : SignerWithAddress,
        keeper : SignerWithAddress,
        feeRecepient : SignerWithAddress;
    let ethOptionMarket: MockOptionMarket;
    let ethOptionMarketViewer: MockOptionViewer;
    let synthetix: MockSynthetix;
    let totalFunds: BigNumber[] = [];
    let totalPremiumCollected: BigNumber[] = [];
    let performanceIndices: BigNumber[] = [];

    before(async () => {
        [ deployer, user0, user1, user2, user3, user4, keeper, feeRecepient ] = await ethers.getSigners();
        const SYSTEM = await deployTestSystem(keeper, feeRecepient);

        ethVault = SYSTEM.ethShortVol;

        await distributeSynths(
            [user0, user1, user2, user3, user4],
            [SYSTEM.sETH, SYSTEM.sUSD, SYSTEM.sBTC],
            [WAD.mul(100), WAD.mul(1000000), BigNumber.from(10).pow(8).mul(10)]
        );

        await batchApprove(
            [user0, user1, user2, user3, user4],
            SYSTEM.sUSD,
            ethVault
        );

        ethOptionMarket = SYSTEM.ethOptionMarket;
        ethOptionMarketViewer = SYSTEM.ethOptionMarketViewer;
        synthetix = SYSTEM.synthetix;
    })

    describe("Round 0", () => {
        it("Should Deposit - I", async () => {
            const tx = await ethVault.connect(user0)["deposit(uint256)"](toBN('10000'));
            await tx.wait();

            const userInfo = await ethVault.userInfos(user0.address);
            expect(userInfo.totalShares).to.be.eq(toBN('10000'));
        })

        it("Should Deposit - II", async () => {
            const amount1 = toBN('60000');
            const amount2 = toBN('70000');
            let tx = await ethVault.connect(user1)["deposit(uint256)"](amount1);
            await tx.wait();

            const userInfo1 = await ethVault.userInfos(user1.address);
            expect(userInfo1.totalShares).to.be.eq(amount1);

            tx = await ethVault.connect(user2)["deposit(uint256)"](amount2);
            await tx.wait();

            const userInfo2 = await ethVault.userInfos(user2.address);
            expect(userInfo2.totalShares).to.be.eq(amount2);

            tx = await ethVault.connect(user0)["deposit(uint256)"](toBN('40000'));
            await tx.wait();

            const userInfo = await ethVault.userInfos(user0.address);
            expect(userInfo.totalShares).to.be.eq(toBN('50000'));
        })

        it("Should Withdraw", async () => {
            const tx = await ethVault.connect(user0).requestWithdraw(toBN('10000'));
            await tx.wait();

            const userInfo = await ethVault.userInfos(user0.address);
            expect(userInfo.totalShares).to.be.eq(toBN('40000'));
        })
    })

    describe("Round 1", () => {
        before(async () => {
            await ethers.provider.send("evm_setNextBlockTimestamp", [VOL_ROUND_TIMESTAMPS[0]]);
            await ethers.provider.send("evm_mine", []);

            await createOptionBoard(
                ethOptionMarket,
                BigNumber.from(VOL_ROUND_TIMESTAMPS[1]),
                toBN('0.8'),
                [toBN('2500'), toBN('2800'), toBN('3200')],
                [toBN('0.9'), toBN('1'), toBN('1.1')]
            );

            let tx;
            tx = await synthetix.setRate(ethers.utils.formatBytes32String("sETH"), toBN('2800'));
            await tx.wait();
            tx = await ethOptionMarket.setPremium('3', toBN('19'));
            await tx.wait();
            tx = await ethOptionMarket.setPremium('1', toBN('23'));
            await tx.wait();
        })

        it("Should start new round", async () => {
            const tx = await ethVault.startNewRound('3', '1'); // 3200 => Call; 2500 => Put;
            await tx.wait();

            const currentRound = await ethVault.currentRound();
            expect(currentRound).to.be.eq(1);

            const totalFundsRound1 = await ethVault.totalFunds();
            totalFunds.push(totalFundsRound1);
        })

        it("Should not sell options (IV_LIMIT_HIT)", async () => {
            await expect(ethVault.connect(keeper).sellOptions(toBN('80000'))).to.be.revertedWith("IV_LIMIT_HIT");
        })

        it("Should sell options - I", async () => {
            const tx = await ethVault.connect(keeper).sellOptions(toBN('50000'));
            await tx.wait();

            const expectedPremium = (50000 / 2800) * (19 + 23);
            const premiumCollected = await ethVault.premiumCollected();
            
            expect(premiumCollected).to.be.closeTo(toBN(String(expectedPremium)), 1e6);
        })

        it("Should sell options - II", async () => {
            const premiumCollectedBefore = await ethVault.premiumCollected();
            let tx;
            tx = await synthetix.setRate(ethers.utils.formatBytes32String("sETH"), toBN('2900'));
            await tx.wait();
            tx = await ethOptionMarket.setPremium('1', toBN('22'));
            await tx.wait();
            tx = await ethOptionMarket.setPremium('3', toBN('20'));
            await tx.wait();

            // SUSD_TO_SPEND_ON_BUYING_ETH = TOTAL_SUSD_REMAINING * ETH_PRICE / (ETH_PRICE + PUT_STRIKE * (1 - FEE))
            // FEE = 0
            tx = await ethVault.connect(keeper).sellOptions(toBN('40469.5767195767'));
            await tx.wait();

            const premiumCollected = await ethVault.premiumCollected();
            const expectedPremium = (40469.57671957672 / 2900) * (22 + 20);

            expect(premiumCollected.sub(premiumCollectedBefore)).to.be.closeTo(toBN(String(expectedPremium)), 1e6);

            totalPremiumCollected.push(premiumCollected);
        })

        it("Should be able to request withdraw", async () => {
            const tx = await ethVault.connect(user0).requestWithdraw(toBN('30000'));
            await tx.wait();

            const userInfo = await ethVault.userInfos(user0.address);
            expect(userInfo.withdrawRound).to.be.eq(1);
            expect(userInfo.withdrawnShares).to.be.eq(toBN('30000'));

            const pendingWithdraws = await ethVault.pendingWithdraws();

            expect(pendingWithdraws).to.be.eq(toBN('30000'));
        })

        it("Should be able to deposit for the next round - I", async () => {
            const tx = await ethVault.connect(user3)["deposit(uint256)"](toBN('100000'));
            await tx.wait();

            const userInfo = await ethVault.userInfos(user3.address);
            expect(userInfo.pendingDeposit).to.be.eq(toBN('100000'));
            expect(userInfo.depositRound).to.be.eq(1);

            const pendingDeposits = await ethVault.pendingDeposits();
            expect(pendingDeposits).to.be.eq(toBN('100000'));
        })

        it("Should be able to deposit for the next round - II", async () => {
            const tx = await ethVault.connect(user2)["deposit(uint256)"](toBN('200000'));
            await tx.wait();

            const userInfo = await ethVault.userInfos(user2.address);
            expect(userInfo.pendingDeposit).to.be.eq(toBN('200000'));
            expect(userInfo.depositRound).to.be.eq(1);

            const pendingDeposits = await ethVault.pendingDeposits();
            expect(pendingDeposits).to.be.eq(toBN('300000'));
        })
    })

    describe("Round 2", () => {
        before(async () => {
            let tx;

            await ethers.provider.send("evm_setNextBlockTimestamp", [VOL_ROUND_TIMESTAMPS[1]]);
            await ethers.provider.send("evm_mine", []);

            tx = await ethOptionMarket.setExpiryPrice('1', toBN('2600'));
            await tx.wait();

            await createOptionBoard(
                ethOptionMarket,
                BigNumber.from(VOL_ROUND_TIMESTAMPS[2]),
                toBN('0.77'),
                [toBN('2300'), toBN('2600'), toBN('3000')],
                [toBN('0.9'), toBN('1'), toBN('1.1')]
            );

            tx = await ethOptionMarket.setPremium('4', toBN('17'));
            await tx.wait();

            tx = await ethOptionMarket.setPremium('6', toBN('20'));
            await tx.wait();
        })

        it("Should not complete withdraw before the round is over", async () => {
            await expect(ethVault.connect(user0).completeWithdraw()).to.be.revertedWith("ROUND_NOT_OVER");
        })

        it("Should start new round", async () => {
            let tx = await synthetix.setRate(ethers.utils.formatBytes32String("sETH"), toBN('2650'));
            await tx.wait();

            tx = await ethVault.startNewRound('6', '4'); // 3000 => Call; 2300 => Put;
            await tx.wait();

            const currentRound = await ethVault.currentRound();
            expect(currentRound).to.be.eq(2);

            // let premium = totalPremiumCollected[0];
            // const feesFromPremium = (premium.mul(1).div(10)).mul(1e8).div(52142857143); // 10%
            // premium = premium.sub(feesFromPremium);

            // let funds = totalFunds[0];
            // const feesFromFunds = (funds.mul(1).div(100)).mul(1e8).div(52142857143); // 1%
            // funds = funds.sub(feesFromFunds);

            // const expectedIndex = premium.add(funds).mul(WAD).div(totalFunds[0]);

            // const index = await ethVault.performanceIndices('1');
            // expect(index).to.be.eq(expectedIndex);

            // performanceIndices.push(index);

            // const totalFundsRound2 = await ethVault.totalFunds();
            // totalFunds.push(totalFundsRound2);
        })
    })
})