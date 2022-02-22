import { ethers, network } from 'hardhat';

export async function deployTestSystem() {
    const Synth = await ethers.getContractFactory("MockSynth");
    const sUSD = await Synth.deploy("Synth USD", "sUSD");
    const sETH = await Synth.deploy("Synth Ethereum", "sETH");
    const sBTC = await Synth.deploy("Synth Bitcoin", "sBTC");

    const Synthetix = await ethers.getContractFactory("MockSynthetix");
    const synthetix = await Synthetix.deploy(
        [sUSD.address, sETH.address, sBTC.address],
        [
            ethers.utils.formatBytes32String("sUSD"),
            ethers.utils.formatBytes32String("sETH"),
            ethers.utils.formatBytes32String("sBTC")
        ]
    );

    const OptionMarketPricer = await ethers.getContractFactory("MockOptionMarketPricer")
    const optionMarketPricer = await OptionMarketPricer.deploy();

    const OptionMarket = await ethers.getContractFactory("MockOptionMarket");
    const OptionMarketViewer = await ethers.getContractFactory("MockOptionViewer");

    const ethOptionMarket = await OptionMarket.deploy(
        sETH.address,
        sUSD.address
    );
    const ethOptionMarketViewer = await OptionMarketViewer.deploy(
        optionMarketPricer.address,
        ethOptionMarket.address,
        {
            optionPriceFeeCoefficient: ethers.BigNumber.from(10).pow(16),
            spotPriceFeeCoefficient: ethers.BigNumber.from(10).pow(14),
            vegaFeeCoefficient: ethers.BigNumber.from(10).pow(18).mul(500),
            vegaNormFactor: ethers.BigNumber.from(10).pow(17).mul(2),
            standardSize: ethers.BigNumber.from(10).pow(18).mul(50),
            skewAdjustmentFactor: ethers.BigNumber.from(10).pow(18),
            rateAndCarry: ethers.BigNumber.from(10).pow(15).mul(6),
            minDelta: ethers.BigNumber.from(10).pow(16),
            volatilityCutoff: ethers.BigNumber.from(10).pow(15).mul(55),
            spotPrice: ethers.BigNumber.from(10).pow(18).mul(2600)
        }
    );

    const btcOptionMarket = await OptionMarket.deploy(
        sBTC.address,
        sUSD.address
    );
    const btcOptionMarketViewer = await OptionMarketViewer.deploy(
        optionMarketPricer.address,
        btcOptionMarket.address,
        {
            optionPriceFeeCoefficient: ethers.BigNumber.from(10).pow(16),
            spotPriceFeeCoefficient: ethers.BigNumber.from(10).pow(14),
            vegaFeeCoefficient: ethers.BigNumber.from(10).pow(18).mul(500),
            vegaNormFactor: ethers.BigNumber.from(10).pow(17).mul(2),
            standardSize: ethers.BigNumber.from(10).pow(17).mul(4),
            skewAdjustmentFactor: ethers.BigNumber.from(10).pow(17),
            rateAndCarry: ethers.BigNumber.from(10).pow(15).mul(6),
            minDelta: ethers.BigNumber.from(10).pow(16),
            volatilityCutoff: ethers.BigNumber.from(10).pow(15).mul(55),
            spotPrice: ethers.BigNumber.from(10).pow(18).mul(37000)
        }
    )

    const CoveredCall = await ethers.getContractFactory("PolynomialCoveredCall");
    const CoveredPut = await ethers.getContractFactory("PolynomialCoveredPut");

    const ethCoveredCall = await CoveredCall.deploy(
        "FX ETH Covered Call",
        sETH.address,
        synthetix.address,
        ethOptionMarket.address,
        ethOptionMarketViewer.address,
        ethers.utils.formatBytes32String("sETH"),
        ethers.utils.formatBytes32String("sUSD")
    );
    const ethCoveredPut = await CoveredPut.deploy(
        "FX ETH Covered Put",
        sUSD.address,
        ethOptionMarket.address,
        ethOptionMarketViewer.address
    );

    const btcCoveredCall = await CoveredCall.deploy(
        "FX BTC Covered Call",
        sBTC.address,
        synthetix.address,
        btcOptionMarket.address,
        btcOptionMarketViewer.address,
        ethers.utils.formatBytes32String("sBTC"),
        ethers.utils.formatBytes32String("sUSD")
    );
    const btcCoveredPut = await CoveredPut.deploy(
        "FX BTC Covered Put",
        sUSD.address,
        btcOptionMarket.address,
        btcOptionMarketViewer.address
    );

    return {
        sUSD,
        sETH,
        sBTC,
        synthetix,
        optionMarketPricer,
        ethOptionMarket,
        ethOptionMarketViewer,
        ethCoveredCall,
        ethCoveredPut,
        btcOptionMarket,
        btcOptionMarketViewer,
        btcCoveredCall,
        btcCoveredPut
    }
}