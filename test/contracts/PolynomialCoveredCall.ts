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
    let totalFunds: BigNumber[] = [];
    let totalPremiumCollected: BigNumber[] = [];
    let performanceIndices: BigNumber[] = [];

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
            const tx = await ethVault.connect(user0)["deposit(uint256)"](toBN('25'));
            await tx.wait();

            const userInfo = await ethVault.userInfos(user0.address);
            expect(userInfo.totalShares).to.be.eq(toBN('25'));
        })

        it("Should Deposit - II", async () => {
            const amount1 = toBN('16.432');
            const amount2 = toBN('0.8753');
            let tx = await ethVault.connect(user1)["deposit(uint256)"](amount1);
            await tx.wait();

            const userInfo1 = await ethVault.userInfos(user1.address);
            expect(userInfo1.totalShares).to.be.eq(amount1);

            tx = await ethVault.connect(user2)["deposit(uint256)"](amount2);
            await tx.wait();

            const userInfo2 = await ethVault.userInfos(user2.address);
            expect(userInfo2.totalShares).to.be.eq(amount2);

            tx = await ethVault.connect(user0)["deposit(uint256)"](toBN('25'));
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
        })

        it("Should start new round", async () => {
            const tx = await ethVault.startNewRound('3'); // 3200 Strike price
            await tx.wait();

            const currentRound = await ethVault.currentRound();
            expect(currentRound).to.be.eq(1);

            const totalFundsRound1 = await ethVault.totalFunds();
            totalFunds.push(totalFundsRound1);
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
            const tx = await ethVault.connect(user0).requestWithdraw(toBN('15'));
            await tx.wait();

            const userInfo = await ethVault.userInfos(user0.address);
            expect(userInfo.withdrawRound).to.be.eq(1);
            expect(userInfo.withdrawnShares).to.be.eq(toBN('15'));

            const pendingWithdraws = await ethVault.pendingWithdraws();

            expect(pendingWithdraws).to.be.eq(toBN('15'));
        })

        it("Should be able to deposit for the next round - I", async () => {
            const tx = await ethVault.connect(user3)["deposit(uint256)"](toBN('50'));
            await tx.wait();

            const userInfo = await ethVault.userInfos(user3.address);
            expect(userInfo.pendingDeposit).to.be.eq(toBN('50'));
            expect(userInfo.depositRound).to.be.eq(1);

            const pendingDeposits = await ethVault.pendingDeposits();
            expect(pendingDeposits).to.be.eq(toBN('50'));
        })

        it("Should be able to deposit for the next round - II", async () => {
            const tx = await ethVault.connect(user2)["deposit(uint256)"](toBN('20'));
            await tx.wait();

            const userInfo = await ethVault.userInfos(user2.address);
            expect(userInfo.pendingDeposit).to.be.eq(toBN('20'));
            expect(userInfo.depositRound).to.be.eq(1);

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

    describe("Round 2", () => {
        before(async () => {
            let tx;

            await ethers.provider.send("evm_setNextBlockTimestamp", [ROUND_TIMESTAMPS[1]]);
            await ethers.provider.send("evm_mine", []);

            tx = await ethOptionMarket.setExpiryPrice('1', toBN('3014'));
            await tx.wait();

            await createOptionBoard(
                ethOptionMarket,
                BigNumber.from(ROUND_TIMESTAMPS[2]),
                toBN('0.77'),
                [toBN('2700'), toBN('3000'), toBN('3400')],
                [toBN('0.9'), toBN('1'), toBN('1.1')]
            );

            tx = await ethOptionMarket.setPremium('6', toBN('22.04'));
            await tx.wait();
        })

        it("Should not complete withdraw before the round is over", async () => {
            await expect(ethVault.connect(user0).completeWithdraw()).to.be.revertedWith("ROUND_NOT_OVER");
        })

        it("Should start new round", async () => {
            const tx = await ethVault.startNewRound('6'); // 3400 Strike price
            await tx.wait();

            const currentRound = await ethVault.currentRound();
            expect(currentRound).to.be.eq(2);

            let premium = totalPremiumCollected[0];
            const feesFromPremium = (premium.mul(1).div(10)).mul(1e8).div(52142857143); // 10%
            premium = premium.sub(feesFromPremium);

            let funds = totalFunds[0];
            const feesFromFunds = (funds.mul(1).div(100)).mul(1e8).div(52142857143); // 1%
            funds = funds.sub(feesFromFunds);

            const expectedIndex = premium.add(funds).mul(WAD).div(totalFunds[0]);

            const index = await ethVault.performanceIndices('1');
            expect(index).to.be.eq(expectedIndex);

            performanceIndices.push(index);

            const totalFundsRound2 = await ethVault.totalFunds();
            totalFunds.push(totalFundsRound2);
        })

        it("Should complete withdraw", async () => {
            const tx = await ethVault.connect(user0).completeWithdraw(); // Requested 15 shares
            const receipt = await tx.wait();

            const completeWithdrawEvent = receipt.events?.find(log => log.event === 'CompleteWithdraw');

            const expectedAmountReceived = performanceIndices[0].mul(15);
            
            expect(completeWithdrawEvent?.args?.user).to.be.eq(user0.address);
            expect(completeWithdrawEvent?.args?.withdrawnRound).to.be.eq(1);
            expect(completeWithdrawEvent?.args?.shares).to.be.eq(toBN('15'));
            expect(completeWithdrawEvent?.args?.funds).to.be.eq(expectedAmountReceived);
        })

        it("Should not sell options (IV_LIMIT_HIT)", async () => {
            await expect(ethVault.connect(keeper).sellOptions(MAX_UINT)).to.be.revertedWith("IV_LIMIT_HIT");
        })

        it("Should sell options - I", async () => {
            const _tx = await synthetix.setRate(ethers.utils.formatBytes32String("sETH"), toBN('3089.14'));
            await _tx.wait();
            const tx = await ethVault.connect(keeper).sellOptions(toBN('20'));
            await tx.wait();

            const expectedPremium = 20 * 22.04 / 3089.14;
            const premiumCollected = await ethVault.premiumCollected();
            
            expect(premiumCollected).to.be.closeTo(toBN(String(expectedPremium)), 1e6);
        })

        it("Should sell options - II", async () => {
            const premiumCollectedBefore = await ethVault.premiumCollected();
            let _tx = await synthetix.setRate(ethers.utils.formatBytes32String("sETH"), toBN('3120'));
            await _tx.wait();
            _tx = await ethOptionMarket.setPremium('6', toBN('40'));
            await _tx.wait();
            const tx = await ethVault.connect(keeper).sellOptions(toBN('20'));
            await tx.wait();

            const premiumCollected = await ethVault.premiumCollected();
            const expectedPremium = 20 * 40 / 3120;

            expect(premiumCollected.sub(premiumCollectedBefore)).to.be.closeTo(toBN(String(expectedPremium)), 1e6);
        })

        it("Should be able to deposit for the next round", async () => {
            const tx = await ethVault.connect(user3)["deposit(uint256)"](toBN('20'));
            await tx.wait();

            const userInfo = await ethVault.userInfos(user3.address); // User has 50 ETH deposit in last round

            const expectedShares = toBN('50').mul(WAD).div(performanceIndices[0]);

            expect(userInfo.pendingDeposit).to.be.eq(toBN('20'));
            expect(userInfo.depositRound).to.be.eq(2);
            expect(userInfo.totalShares).to.be.eq(expectedShares);

            const pendingDeposits = await ethVault.pendingDeposits();
            expect(pendingDeposits).to.be.eq(toBN('20'));
        })

        it("Should sell options - III", async () => {
            let tx;

            for (let index = 0; index < 3; index++) {
                tx = await ethVault.connect(keeper).sellOptions(toBN('20'));
                await tx.wait();
            }

            const premiumCollected = await ethVault.premiumCollected();
            totalPremiumCollected.push(premiumCollected);
        })

        it("Should be able to request withdraw - I", async () => {
            let userInfo = await ethVault.userInfos(user1.address);
            const totalShares = userInfo.totalShares;
            const tx = await ethVault.connect(user1).requestWithdraw(toBN('1'));
            await tx.wait();

            userInfo = await ethVault.userInfos(user1.address);
            expect(userInfo.withdrawRound).to.be.eq(2);
            expect(userInfo.withdrawnShares).to.be.eq(toBN('1'));
            expect(userInfo.totalShares).to.be.eq(totalShares.sub(toBN('1')));

            const pendingWithdraws = await ethVault.pendingWithdraws();

            expect(pendingWithdraws).to.be.eq(toBN('1'));
        })

        it("Should be able to request withdraw - II", async () => {
            let userInfo = await ethVault.userInfos(user2.address);
            const totalShares = userInfo.totalShares;
            const tx = await ethVault.connect(user2).requestWithdraw(toBN('0.5'));
            await tx.wait();

            userInfo = await ethVault.userInfos(user2.address);
            expect(userInfo.withdrawRound).to.be.eq(2);
            expect(userInfo.withdrawnShares).to.be.eq(toBN('0.5'));
            expect(userInfo.totalShares).to.be.eq(totalShares.sub(toBN('0.5')));

            const pendingWithdraws = await ethVault.pendingWithdraws();

            expect(pendingWithdraws).to.be.eq(toBN('1.5'));
        })

        it("Should be able to cancel withdraw", async () => {
            let userInfo = await ethVault.userInfos(user2.address);
            const totalShares = userInfo.totalShares;

            const tx = await ethVault.connect(user2).cancelWithdraw(toBN('0.5'));
            await tx.wait();

            userInfo = await ethVault.userInfos(user2.address);
            expect(userInfo.withdrawnShares).to.be.eq(0);
            expect(userInfo.totalShares).to.be.eq(totalShares.add(toBN('0.5')));

            const pendingWithdraws = await ethVault.pendingWithdraws();

            expect(pendingWithdraws).to.be.eq(toBN('1'));
        })
    })

    describe("Round 3", () => {
        before(async () => {
            let tx;

            await ethers.provider.send("evm_setNextBlockTimestamp", [ROUND_TIMESTAMPS[2]]);
            await ethers.provider.send("evm_mine", []);

            tx = await ethOptionMarket.setExpiryPrice('2', toBN('3459'));
            await tx.wait();

            await createOptionBoard(
                ethOptionMarket,
                BigNumber.from(ROUND_TIMESTAMPS[3]),
                toBN('0.75'),
                [toBN('3000'), toBN('3400'), toBN('3800')],
                [toBN('0.9'), toBN('1'), toBN('1.1')]
            );

            tx = await ethOptionMarket.setPremium('9', toBN('35.07'));
            await tx.wait();
        })

        it("Should start new round", async () => {
            const tx = await ethVault.startNewRound('9'); // 3400 Strike price
            await tx.wait();

            const currentRound = await ethVault.currentRound();
            expect(currentRound).to.be.eq(3);

            const premium = totalPremiumCollected[1]; // No fees as last round ended in a loss

            const funds = totalFunds[1].mul(3400).div(3459); // ETH expired higher than last strike

            const expectedIndex = performanceIndices[0].mul(premium.add(funds).mul(WAD).div(totalFunds[1])).div(WAD);

            const index = await ethVault.performanceIndices('2');
            expect(index).to.be.eq(expectedIndex);

            performanceIndices.push(index);
        })

        it("Should complete withdraw", async () => {
            const tx = await ethVault.connect(user1).completeWithdraw(); // Requested 1 shares
            const receipt = await tx.wait();

            const completeWithdrawEvent = receipt.events?.find(log => log.event === 'CompleteWithdraw');

            const expectedAmountReceived = performanceIndices[1];
            
            expect(completeWithdrawEvent?.args?.user).to.be.eq(user1.address);
            expect(completeWithdrawEvent?.args?.withdrawnRound).to.be.eq(2);
            expect(completeWithdrawEvent?.args?.shares).to.be.eq(toBN('1'));
            expect(completeWithdrawEvent?.args?.funds).to.be.eq(expectedAmountReceived);
        })

        it("Should sell options - I", async () => {
            const _tx = await synthetix.setRate(ethers.utils.formatBytes32String("sETH"), toBN('3357.14'));
            await _tx.wait();
            const tx = await ethVault.connect(keeper).sellOptions(toBN('20'));
            await tx.wait();

            const expectedPremium = 20 * 35.07 / 3357.14;
            const premiumCollected = await ethVault.premiumCollected();
            
            expect(premiumCollected).to.be.closeTo(toBN(String(expectedPremium)), 1e6);
        })

        it("Should sell options - II", async () => {
            let tx;

            for (let index = 0; index < 3; index++) {
                tx = await ethVault.connect(keeper).sellOptions(toBN('20'));
                await tx.wait();
            }

            const premiumCollected = await ethVault.premiumCollected();
            totalPremiumCollected.push(premiumCollected);
        })
    })
})