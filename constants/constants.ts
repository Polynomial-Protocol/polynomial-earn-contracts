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
    },
    "optimistic_kovan": {
        "SUSD": "0x84B6b512E8F416981a27d33E210A1886e29791aB",
        "SETH": "0x2818E5083696E6EB78613b40c0f18Eb47bE55701",
        "SBTC": "0xd87d92fbBe1E7AEaC166Df5F43cA293820edDc37"
    }
}

export const SYNTHETIX_ADDR: KV = {
    "optimism": "0x8700dAec35aF8Ff88c16BdF0418774CB3D7599B4",
    "optimistic_kovan": "0x4194f283bC35521Ab503Fc2c4ee42E4Dc9aE10Ff"
}

export const LYRA_MARKET: NestedKV = {
    "optimism": {
        "SETH": "0x1f6D98638Eee9f689684767C3021230Dd68df419",
        "SBTC": "0x47B5BB79F06F06db3D77C6cc4DB1ad6E84faF1f4"
    },
    "optimistic_kovan": {
        "SETH": "0xb43285B5aF7cad80409e1267Ea21ECB44eEF4a0E",
        "SBTC": "0xFDD1C82738521dafA5d107805751a921ee6E6c5D"
    }
}

export const MARKET_PRICER: NestedKV = {
    "optimism": {
        "SETH": "0x39A023FDe14d44c01bcb43993B3A51117174F336",
        "SBTC": "0xC1729854837578dC867C6d644304407F0EBc5A3D"
    },
    "optimistic_kovan": {
        "SETH": "0x88eD3b6a393389F06eD9c943bA041eefBcd97492",
        "SBTC": "0x8A65A851641c65EA5cadf7eb2729f9dF55925B7C"
    }
}

export const MARKET_VIEWER: NestedKV = {
    "optimism": {
        "SETH": "0x43592bffCF14f1e0A096091E125f023B2ccC2525",
        "SBTC": "0x22c39cE1C3A49224Aea6D8c2AAa0019828E1b5E4"
    },
    "optimistic_kovan": {
        "SETH": "0x8739873A3162F4B02cAD3e4c928Fa8549384B9Fe",
        "SBTC": "0x8D4792837e4072E466261264193BFa09Fc721f3E"
    }
}

export const SYNTH_KEYS: KV = {
    "SETH": ethers.utils.formatBytes32String("sETH"),
    "SBTC": ethers.utils.formatBytes32String("sBTC"),
    "SUSD": ethers.utils.formatBytes32String("sUSD")
}

export const ROUND_TIMESTAMPS = [1643961600, 1644566400, 1645171200, 1645776000]

export const PUT_ROUND_TIMESTAMPS = [1648800000, 1649404800, 1650009600, 1650614400]
