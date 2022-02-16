// SPDX-License-Identifier: ISC
pragma solidity 0.8.9;

import { IOptionMarket } from "./IOptionMarket.sol";

interface IOptionMarketViewer {
    struct TradePremiumView {
        uint listingId;
        uint premium;
        uint basePrice;
        uint vegaUtilFee;
        uint optionPriceFee;
        uint spotPriceFee;
        uint newIv;
    }

    function getPremiumForOpen(
        uint _listingId,
        IOptionMarket.TradeType tradeType,
        uint amount
    ) external view returns (TradePremiumView memory);
}