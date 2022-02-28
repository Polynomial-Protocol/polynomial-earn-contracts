import { expect } from "chai";
import { ethers, network } from "hardhat";
import { deployTestSystem } from "../utils/deployTestSystem";
import { distributeSynths } from "../utils/distributeSynths";
import { BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { batchApprove } from "../utils/batchApprove";
import { PUT_ROUND_TIMESTAMPS } from "../../constants/constants";
import { createOptionBoard } from "../utils/createOptionBoard";
import { MockOptionMarket, MockOptionViewer, MockSynthetix, PolynomialCoveredPut } from "../../typechain";
import { toBN } from "../../scripts/utils/general/toBN";

describe("PolynomialCoveredPut", () => {
    let ethVault : PolynomialCoveredPut;
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

        ethVault = SYSTEM.ethCoveredPut;

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
            const amount1 = toBN('20000');
            const amount2 = toBN('50000');
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
            await ethers.provider.send("evm_setNextBlockTimestamp", [PUT_ROUND_TIMESTAMPS[0]]);
            await ethers.provider.send("evm_mine", []);

            await createOptionBoard(
                ethOptionMarket,
                BigNumber.from(PUT_ROUND_TIMESTAMPS[1]),
                toBN('0.8'),
                [toBN('2500'), toBN('2800'), toBN('3200')],
                [toBN('0.9'), toBN('1'), toBN('1.1')]
            );

            const tx = await ethOptionMarket.setPremium('1', toBN('23'));
            await tx.wait();
        })

        it("Should start new round", async () => {
            const tx = await ethVault.startNewRound('1'); // 2500 Strike price
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
            const tx = await ethVault.connect(keeper).sellOptions(toBN('20'));
            await tx.wait();

            const expectedPremium = 20 * 23;
            const premiumCollected = await ethVault.premiumCollected();
            
            expect(premiumCollected).to.be.closeTo(toBN(String(expectedPremium)), 1e6);
        })

        it("Should sell options - II", async () => {
            const premiumCollectedBefore = await ethVault.premiumCollected();
            const _tx = await ethOptionMarket.setPremium('1', toBN('22'));
            await _tx.wait();
            const tx = await ethVault.connect(keeper).sellOptions(toBN('20'));
            await tx.wait();

            const premiumCollected = await ethVault.premiumCollected();
            const expectedPremium = 20 * 22;

            expect(premiumCollected.sub(premiumCollectedBefore)).to.be.closeTo(toBN(String(expectedPremium)), 1e6);
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

        it("Should sell options - III", async () => {
            const _tx = await ethOptionMarket.setPremium('1', toBN('24'));
            await _tx.wait();
            const tx = await ethVault.connect(keeper).sellOptions(MAX_UINT);
            const receipt = await tx.wait();

            const optionsSoldEvent = receipt.events?.find(log => log.event === 'SellOptions');
            expect(optionsSoldEvent?.args?.optionsSold).to.be.closeTo(toBN('4'), 1e6);

            const premiumCollected = await ethVault.premiumCollected();
            totalPremiumCollected.push(premiumCollected);
        })
    })

    describe("Round 2", () => {
        before(async () => {
            let tx;

            await ethers.provider.send("evm_setNextBlockTimestamp", [PUT_ROUND_TIMESTAMPS[1]]);
            await ethers.provider.send("evm_mine", []);

            tx = await ethOptionMarket.setExpiryPrice('1', toBN('2600'));
            await tx.wait();

            await createOptionBoard(
                ethOptionMarket,
                BigNumber.from(PUT_ROUND_TIMESTAMPS[2]),
                toBN('0.77'),
                [toBN('2300'), toBN('2600'), toBN('3000')],
                [toBN('0.9'), toBN('1'), toBN('1.1')]
            );

            tx = await ethOptionMarket.setPremium('4', toBN('17'));
            await tx.wait();
        })

        it("Should not complete withdraw before the round is over", async () => {
            await expect(ethVault.connect(user0).completeWithdraw()).to.be.revertedWith("ROUND_NOT_OVER");
        })

        it("Should start new round", async () => {
            const tx = await ethVault.startNewRound('4'); // 2300 Strike price
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
            const tx = await ethVault.connect(user0).completeWithdraw(); // Requested 30000 shares
            const receipt = await tx.wait();

            const completeWithdrawEvent = receipt.events?.find(log => log.event === 'CompleteWithdraw');

            const expectedAmountReceived = performanceIndices[0].mul(30000);
            
            expect(completeWithdrawEvent?.args?.user).to.be.eq(user0.address);
            expect(completeWithdrawEvent?.args?.withdrawnRound).to.be.eq(1);
            expect(completeWithdrawEvent?.args?.shares).to.be.eq(toBN('30000'));
            expect(completeWithdrawEvent?.args?.funds).to.be.eq(expectedAmountReceived);
        })

        it("Should not sell options (IV_LIMIT_HIT)", async () => {
            await expect(ethVault.connect(keeper).sellOptions(MAX_UINT)).to.be.revertedWith("IV_LIMIT_HIT");
        })

        it("Should sell options - I", async () => {
            const tx = await ethVault.connect(keeper).sellOptions(toBN('20'));
            await tx.wait();

            const expectedPremium = 20 * 17;
            const premiumCollected = await ethVault.premiumCollected();
            
            expect(premiumCollected).to.be.closeTo(toBN(String(expectedPremium)), 1e6);
        })

        it("Should sell options - II", async () => {
            const premiumCollectedBefore = await ethVault.premiumCollected();
            const _tx = await ethOptionMarket.setPremium('4', toBN('23'));
            await _tx.wait();
            const tx = await ethVault.connect(keeper).sellOptions(toBN('20'));
            await tx.wait();

            const premiumCollected = await ethVault.premiumCollected();
            const expectedPremium = 20 * 23;

            expect(premiumCollected.sub(premiumCollectedBefore)).to.be.closeTo(toBN(String(expectedPremium)), 1e6);
        })

        it("Should be able to deposit for the next round", async () => {
            const tx = await ethVault.connect(user3)["deposit(uint256)"](toBN('20000'));
            await tx.wait();

            const userInfo = await ethVault.userInfos(user3.address); // User has 100000 sUSD deposit in last round

            const expectedShares = toBN('100000').mul(WAD).div(performanceIndices[0]);

            expect(userInfo.pendingDeposit).to.be.eq(toBN('20000'));
            expect(userInfo.depositRound).to.be.eq(2);
            expect(userInfo.totalShares).to.be.eq(expectedShares);

            const pendingDeposits = await ethVault.pendingDeposits();
            expect(pendingDeposits).to.be.eq(toBN('20000'));
        })

        it("Should sell options - III", async () => {
            let tx;

            for (let index = 0; index < 5; index++) {
                tx = await ethVault.connect(keeper).sellOptions(toBN('20'));
                await tx.wait();
            }

            tx = await ethVault.connect(keeper).sellOptions(MAX_UINT);
            await tx.wait();

            const premiumCollected = await ethVault.premiumCollected();
            totalPremiumCollected.push(premiumCollected);
        })

        it("Should be able to request withdraw - I", async () => {
            let userInfo = await ethVault.userInfos(user1.address);
            const totalShares = userInfo.totalShares;
            const tx = await ethVault.connect(user1).requestWithdraw(toBN('10000'));
            await tx.wait();

            userInfo = await ethVault.userInfos(user1.address);
            expect(userInfo.withdrawRound).to.be.eq(2);
            expect(userInfo.withdrawnShares).to.be.eq(toBN('10000'));
            expect(userInfo.totalShares).to.be.eq(totalShares.sub(toBN('10000')));

            const pendingWithdraws = await ethVault.pendingWithdraws();

            expect(pendingWithdraws).to.be.eq(toBN('10000'));
        })

        it("Should be able to request withdraw - II", async () => {
            let userInfo = await ethVault.userInfos(user2.address);
            const totalShares = userInfo.totalShares;
            const tx = await ethVault.connect(user2).requestWithdraw(toBN('50000'));
            await tx.wait();

            userInfo = await ethVault.userInfos(user2.address);
            expect(userInfo.withdrawRound).to.be.eq(2);
            expect(userInfo.withdrawnShares).to.be.eq(toBN('50000'));
            expect(userInfo.totalShares).to.be.eq(totalShares.sub(toBN('50000')));

            const pendingWithdraws = await ethVault.pendingWithdraws();

            expect(pendingWithdraws).to.be.eq(toBN('60000'));
        })

        it("Should be able to cancel withdraw", async () => {
            let userInfo = await ethVault.userInfos(user2.address);
            const totalShares = userInfo.totalShares;

            const tx = await ethVault.connect(user2).cancelWithdraw(toBN('50000'));
            await tx.wait();

            userInfo = await ethVault.userInfos(user2.address);
            expect(userInfo.withdrawnShares).to.be.eq(0);
            expect(userInfo.totalShares).to.be.eq(totalShares.add(toBN('50000')));

            const pendingWithdraws = await ethVault.pendingWithdraws();

            expect(pendingWithdraws).to.be.eq(toBN('10000'));
        })
    })

    describe("Round 3", () => {
        before(async () => {
            let tx;

            await ethers.provider.send("evm_setNextBlockTimestamp", [PUT_ROUND_TIMESTAMPS[2]]);
            await ethers.provider.send("evm_mine", []);

            tx = await ethOptionMarket.setExpiryPrice('2', toBN('2200'));
            await tx.wait();

            await createOptionBoard(
                ethOptionMarket,
                BigNumber.from(PUT_ROUND_TIMESTAMPS[3]),
                toBN('0.75'),
                [toBN('1800'), toBN('2100'), toBN('2600')],
                [toBN('0.9'), toBN('1'), toBN('1.1')]
            );

            tx = await ethOptionMarket.setPremium('7', toBN('7'));
            await tx.wait();
        })

        it("Should start new round", async () => {
            const tx = await ethVault.startNewRound('7'); // 3400 Strike price
            await tx.wait();

            const currentRound = await ethVault.currentRound();
            expect(currentRound).to.be.eq(3);

            const premium = totalPremiumCollected[1]; // No fees as last round ended in a loss

            const funds = totalFunds[1].mul(2200).div(2300); // ETH expired higher than last strike

            const expectedIndex = performanceIndices[0].mul(premium.add(funds).mul(WAD).div(totalFunds[1])).div(WAD);

            const index = await ethVault.performanceIndices('2');
            expect(index).to.be.closeTo(expectedIndex, 10);

            performanceIndices.push(index);
        })

        it("Should complete withdraw", async () => {
            const tx = await ethVault.connect(user1).completeWithdraw(); // Requested 10000 shares
            const receipt = await tx.wait();

            const completeWithdrawEvent = receipt.events?.find(log => log.event === 'CompleteWithdraw');

            const expectedAmountReceived = performanceIndices[1].mul(10000);
            
            expect(completeWithdrawEvent?.args?.user).to.be.eq(user1.address);
            expect(completeWithdrawEvent?.args?.withdrawnRound).to.be.eq(2);
            expect(completeWithdrawEvent?.args?.shares).to.be.eq(toBN('10000'));
            expect(completeWithdrawEvent?.args?.funds).to.be.eq(expectedAmountReceived);
        })

        it("Should sell options - I", async () => {
            const tx = await ethVault.connect(keeper).sellOptions(toBN('20'));
            await tx.wait();

            const expectedPremium = 20 * 7;
            const premiumCollected = await ethVault.premiumCollected();
            
            expect(premiumCollected).to.be.closeTo(toBN(String(expectedPremium)), 1e6);
        })

        it("Should sell options - II", async () => {
            let tx;

            for (let index = 0; index < 8; index++) {
                tx = await ethVault.connect(keeper).sellOptions(toBN('20'));
                await tx.wait();
            }

            tx = await ethVault.connect(keeper).sellOptions(MAX_UINT);
            await tx.wait();

            const premiumCollected = await ethVault.premiumCollected();
            totalPremiumCollected.push(premiumCollected);
        })
    })
})