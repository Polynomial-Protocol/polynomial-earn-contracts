import { ethers } from "ethers";

/// Constants

interface KV {
    [key: string]: string
}

interface NestedKV {
    [key: string]: KV
}

export const TOKEN_ADDR: NestedKV = {
    "optimism": {
        "SUSD": "0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9",
        "SETH": "0xE405de8F52ba7559f9df3C368500B6E6ae6Cee49",
        "SBTC": "0x298B9B95708152ff6968aafd889c6586e9169f1D"
    }
}

export const SYNTHETIX_ADDR: KV = {
    "optimism": "0x8700dAec35aF8Ff88c16BdF0418774CB3D7599B4"
}

export const LYRA_MARKET: NestedKV = {
    "optimism": {
        "SETH": "0x1f6D98638Eee9f689684767C3021230Dd68df419",
        "SBTC": "0x47B5BB79F06F06db3D77C6cc4DB1ad6E84faF1f4"
    }
}

export const MARKET_PRICER: NestedKV = {
    "optimism": {
        "SETH": "0x39A023FDe14d44c01bcb43993B3A51117174F336",
        "SBTC": "0xC1729854837578dC867C6d644304407F0EBc5A3D"
    }
}

export const MARKET_VIEWER: NestedKV = {
    "optimism": {
        "SETH": "0x43592bffCF14f1e0A096091E125f023B2ccC2525",
        "SBTC": "0x22c39cE1C3A49224Aea6D8c2AAa0019828E1b5E4"
    }
}

export const SYNTH_KEYS: KV = {
    "SETH": ethers.utils.formatBytes32String("sETH"),
    "SBTC": ethers.utils.formatBytes32String("sBTC"),
    "SUSD": ethers.utils.formatBytes32String("sUSD")
}

export const ROUND_TIMESTAMPS = [1643961600, 1644566400, 1645171200, 1645776000]

export const PUT_ROUND_TIMESTAMPS = [1648800000, 1649404800, 1650009600, 1650614400]
