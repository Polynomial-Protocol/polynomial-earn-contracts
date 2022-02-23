import { expect } from "chai";
import { ethers, network } from "hardhat";
import { deployTestSystem } from "../utils/deployTestSystem";
import { distributeSynths } from "../utils/distributeSynths";
import { BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { batchApprove } from "../utils/batchApprove";
import { ROUND_TIMESTAMPS } from "../../constants/constants";
import { createOptionBoard } from "../utils/createOptionBoard";
import { MockOptionMarket, MockOptionViewer, MockSynthetix, PolynomialCoveredCall } from "../../typechain";
import { toBN } from "../../scripts/utils/general/toBN";

describe("PolynomialCoveredCall", () => {
    let ethVault : PolynomialCoveredCall, btcVault : PolynomialCoveredCall;
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
    let totalFunds: BigNumber[];
    let totalPremiumCollected: BigNumber[];

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

        ethOptionMarket = SYSTEM.ethOptionMarket;
        ethOptionMarketViewer = SYSTEM.ethOptionMarketViewer;
        synthetix = SYSTEM.synthetix;
    })

    describe("Round 0", () => {
        it("Should Deposit - I", async () => {
            const tx = await ethVault.connect(user0).depositForRoundZero(toBN('25'));
            await tx.wait();

            const userInfo = await ethVault.userInfos(user0.address);
            expect(userInfo.totalShares).to.be.eq(toBN('25'));
        })

        it("Should Deposit - II", async () => {
            const amount1 = toBN('16.432');
            const amount2 = toBN('0.8753');
            let tx = await ethVault.connect(user1).depositForRoundZero(amount1);
            await tx.wait();

            const userInfo1 = await ethVault.userInfos(user1.address);
            expect(userInfo1.totalShares).to.be.eq(amount1);

            tx = await ethVault.connect(user2).depositForRoundZero(amount2);
            await tx.wait();

            const userInfo2 = await ethVault.userInfos(user2.address);
            expect(userInfo2.totalShares).to.be.eq(amount2);

            tx = await ethVault.connect(user0).depositForRoundZero(toBN('25'));
            await tx.wait();

            const userInfo = await ethVault.userInfos(user0.address);
            expect(userInfo.totalShares).to.be.eq(toBN('50'));
        })

        it("Should Withdraw", async () => {
            const tx = await ethVault.connect(user0).requestWithdraw(toBN('25'));
            await tx.wait();

            const userInfo = await ethVault.userInfos(user0.address);
            expect(userInfo.totalShares).to.be.eq(toBN('25'));
        })
    })

    describe("Round 1", () => {
        before(async () => {
            await ethers.provider.send("evm_setNextBlockTimestamp", [ROUND_TIMESTAMPS[0]]);
            await ethers.provider.send("evm_mine", []);

            await createOptionBoard(
                ethOptionMarket,
                BigNumber.from(ROUND_TIMESTAMPS[1]),
                toBN('0.8'),
                [toBN('2500'), toBN('2800'), toBN('3200')],
                [toBN('0.9'), toBN('1'), toBN('1.1')]
            );

            const tx = await ethOptionMarket.setPremium('3', toBN('19'));
            await tx.wait();

            const totalFundsRound1 = await ethVault.totalFunds();
            totalFunds.push(totalFundsRound1);
        })

        it("Should start new round", async () => {
            const tx = await ethVault.startNewRound('3'); // 3200 Strike price
            await tx.wait();

            const currentRound = await ethVault.currentRound();
            expect(currentRound).to.be.eq(1);
        })

        it("Should not sell options (IV_LIMIT_HIT)", async () => {
            await expect(ethVault.connect(keeper).sellOptions(MAX_UINT)).to.be.revertedWith("IV_LIMIT_HIT");
        })

        it("Should sell options - I", async () => {
            const _tx = await synthetix.setRate(ethers.utils.formatBytes32String("sETH"), toBN('2805.35'));
            await _tx.wait();
            const tx = await ethVault.connect(keeper).sellOptions(toBN('20'));
            await tx.wait();

            const expectedPremium = 20 * 19 / 2805.35;
            const premiumCollected = await ethVault.premiumCollected();
            
            expect(premiumCollected).to.be.closeTo(toBN(String(expectedPremium)), 1e6);
        })

        it("Should sell options - II", async () => {
            const premiumCollectedBefore = await ethVault.premiumCollected();
            let _tx = await synthetix.setRate(ethers.utils.formatBytes32String("sETH"), toBN('2791.54'));
            await _tx.wait();
            _tx = await ethOptionMarket.setPremium('3', toBN('18.74'));
            await _tx.wait();
            const tx = await ethVault.connect(keeper).sellOptions(toBN('20'));
            await tx.wait();

            const premiumCollected = await ethVault.premiumCollected();
            const expectedPremium = 20 * 18.74 / 2791.54;

            expect(premiumCollected.sub(premiumCollectedBefore)).to.be.closeTo(toBN(String(expectedPremium)), 1e6);
        })

        it("Should be able to request withdraw", async () => {
            const tx = await ethVault.connect(user0).requestWithdraw(toBN('5'));
            await tx.wait();

            const userInfo = await ethVault.userInfos(user0.address);
            expect(userInfo.withdrawRound).to.be.eq(1);
            expect(userInfo.withdrawnShares).to.be.eq(toBN('5'));

            const pendingWithdraws = await ethVault.pendingWithdraws();

            expect(pendingWithdraws).to.be.eq(toBN('5'));
        })

        it("Should be able to deposit for the next round - I", async () => {
            const tx = await ethVault.connect(user3).deposit(toBN('50'));
            await tx.wait();

            const userInfo = await ethVault.userInfos(user3.address);
            expect(userInfo.pendingDeposit).to.be.eq(toBN('50'));
            expect(userInfo.depositRound).to.be.eq(2);

            const pendingDeposits = await ethVault.pendingDeposits();
            expect(pendingDeposits).to.be.eq(toBN('50'));
        })

        it("Should be able to deposit for the next round - II", async () => {
            const tx = await ethVault.connect(user2).deposit(toBN('20'));
            await tx.wait();

            const userInfo = await ethVault.userInfos(user2.address);
            expect(userInfo.pendingDeposit).to.be.eq(toBN('20'));
            expect(userInfo.depositRound).to.be.eq(2);

            const pendingDeposits = await ethVault.pendingDeposits();
            expect(pendingDeposits).to.be.eq(toBN('70'));
        })

        it("Should sell options - III", async () => {
            let _tx = await synthetix.setRate(ethers.utils.formatBytes32String("sETH"), toBN('2834.51'));
            await _tx.wait();
            _tx = await ethOptionMarket.setPremium('3', toBN('19.78'));
            await _tx.wait();
            const tx = await ethVault.connect(keeper).sellOptions(MAX_UINT);
            const receipt = await tx.wait();

            const optionsSoldEvent = receipt.events?.find(log => log.event === 'SellOptions');
            expect(optionsSoldEvent?.args?.optionsSold).to.be.closeTo(toBN('2.3073'), 1e6);

            const premiumCollected = await ethVault.premiumCollected();
            totalPremiumCollected.push(premiumCollected);
        })
    })
})