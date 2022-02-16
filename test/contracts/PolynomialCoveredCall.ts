import { expect } from "chai";
import { ethers, network } from "hardhat";
import { deployVault } from "../utils/deployVault";
import { getERC20 } from "../../scripts/utils/general/getERC20";
import { TOKEN_ADDR } from "../../constants/constants";
import { BigNumber, Contract, Signer } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

describe("PolynomialCoveredCall", () => {
    let ethVault : Contract, btcVault : Contract;
    let networkName : string;
    const WAD = BigNumber.from(10).pow(18);
    const MAX_UINT = BigNumber.from(2).pow(256).sub(1);
    let deployer : SignerWithAddress,
        user0 : SignerWithAddress,
        user1 : SignerWithAddress,
        user2 : SignerWithAddress,
        user3 : SignerWithAddress,
        user4 : SignerWithAddress,
        sethWhale : SignerWithAddress;
    let SETH : Contract;

    before(async () => {
        ethVault = await deployVault("SETH", "coveredCall");
        btcVault = await deployVault("SBTC", "coveredCall");

        const sethWhaleAddr = "0xa5f7a39E55D7878bC5bd754eE5d6BD7a7662355b";

        const networkName = network.name === "hardhat" ? "optimism" : network.name;
        [deployer, user0, user1, user2, user3, user4] = await ethers.getSigners();

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [sethWhaleAddr],
        });

        sethWhale = await ethers.getSigner(sethWhaleAddr);

        const seth = await getERC20(TOKEN_ADDR[networkName]["SETH"], sethWhale);
        SETH = seth;

        const amount = WAD.mul(100);
        
        let tx = await seth.transfer(user0.address, amount);
        await tx.wait();

        tx = await seth.transfer(user1.address, amount);
        await tx.wait();

        tx = await seth.transfer(user2.address, amount);
        await tx.wait();

        tx = await seth.transfer(user3.address, amount);
        await tx.wait();

        tx = await seth.transfer(user4.address, amount);
        await tx.wait();

        tx = await seth.connect(user0).approve(ethVault.address, MAX_UINT);
        await tx.wait();

        tx = await seth.connect(user1).approve(ethVault.address, MAX_UINT);
        await tx.wait();

        tx = await seth.connect(user2).approve(ethVault.address, MAX_UINT);
        await tx.wait();

        tx = await seth.connect(user3).approve(ethVault.address, MAX_UINT);
        await tx.wait();

        tx = await seth.connect(user4).approve(ethVault.address, MAX_UINT);
        await tx.wait();

        tx = await ethVault.setCap(MAX_UINT);
        await tx.wait();

        tx = await ethVault.setUserDepositLimit(MAX_UINT);
        await tx.wait();
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