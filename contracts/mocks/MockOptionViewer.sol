// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import { ILyraGlobals } from "../interfaces/lyra/ILyraGlobals.sol";
import { ILiquidityPool } from "../interfaces/lyra/ILiquidityPool.sol";
import { IOptionMarketViewer } from "../interfaces/lyra/IOptionMarketViewer.sol";
import { IOptionMarket } from "../interfaces/lyra/IOptionMarket.sol";
import { IOptionMarketPricer } from "../interfaces/lyra/IOptionMarketPricer.sol";
import { SafeDecimalMath } from "../synthetix/SafeDecimalMath.sol";

contract MockOptionViewer is IOptionMarketViewer {
    using SafeDecimalMath for uint;

    address owner;
    IOptionMarketPricer optionMarketPricer;
    IOptionMarket optionMarket;
    ILyraGlobals.PricingGlobals public pricingGlobals;

    constructor(IOptionMarketPricer _pricer, IOptionMarket _market, ILyraGlobals.PricingGlobals memory _pricingGlobals) {
        owner = msg.sender;
        optionMarketPricer = _pricer;
        optionMarket = _market;
        pricingGlobals = _pricingGlobals;
    }

    function getPremiumForOpen(
        uint _listingId,
        IOptionMarket.TradeType tradeType,
        uint amount
    ) external view override returns (TradePremiumView memory) {
        bool isBuy = tradeType == IOptionMarket.TradeType.LONG_CALL || tradeType == IOptionMarket.TradeType.LONG_PUT;
        return getPremiumForTrade(_listingId, tradeType, isBuy, amount);
    }

    function getPremiumForTrade(
        uint _listingId,
        IOptionMarket.TradeType tradeType,
        bool isBuy,
        uint amount
    ) public view returns (TradePremiumView memory) {
        ILiquidityPool.Liquidity memory liq;
        IOptionMarket.OptionListing memory listing = getListing(_listingId);
        IOptionMarket.OptionBoard memory board = getBoard(listing.boardId);
        IOptionMarket.Trade memory trade =
        IOptionMarket.Trade({
            isBuy: isBuy,
            amount: amount,
            vol: board.iv.multiplyDecimal(listing.skew),
            expiry: board.expiry,
            liquidity: liq
        });
        bool isCall = tradeType == IOptionMarket.TradeType.LONG_CALL || tradeType == IOptionMarket.TradeType.SHORT_CALL;
        return _getPremiumForTrade(listing, board, trade, pricingGlobals, isCall);
    }

    function _getPremiumForTrade(
        IOptionMarket.OptionListing memory listing,
        IOptionMarket.OptionBoard memory board,
        IOptionMarket.Trade memory trade,
        ILyraGlobals.PricingGlobals memory _pricingGlobals,
        bool isCall
    ) public view returns (TradePremiumView memory premium) {

        (uint newIv, uint newSkew) = optionMarketPricer.ivImpactForTrade(listing, trade, _pricingGlobals, board.iv);
        trade.vol = newIv.multiplyDecimal(newSkew);

        premium.newIv = trade.vol;
    }

    function getBoard(uint boardId) public view returns (IOptionMarket.OptionBoard memory) {
        (uint id, uint expiry, uint iv, ) = optionMarket.optionBoards(boardId);
        uint[] memory listings = optionMarket.getBoardListings(boardId);
        return IOptionMarket.OptionBoard(id, expiry, iv, false, listings);
    }

    function getListing(uint listingId) public view returns (IOptionMarket.OptionListing memory) {
        (uint id, uint strike, uint skew, uint longCall, uint shortCall, uint longPut, uint shortPut, uint boardId) =
            optionMarket.optionListings(listingId);
        return IOptionMarket.OptionListing(id, strike, skew, longCall, shortCall, longPut, shortPut, boardId);
    }

    function getPricingGlobals() public view returns (ILyraGlobals.PricingGlobals memory) {
        return pricingGlobals;
    }

}
