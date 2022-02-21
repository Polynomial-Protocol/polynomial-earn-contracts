// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import { IOptionMarket } from "../interfaces/lyra/IOptionMarket.sol";
import { ILyraGlobals } from "../interfaces/lyra/ILyraGlobals.sol";
import { SafeDecimalMath } from "../synthetix/SafeDecimalMath.sol";

contract MockOptionMarketPricer {
    using SafeDecimalMath for uint;

    function ivImpactForTrade(
        IOptionMarket.OptionListing memory listing,
        IOptionMarket.Trade memory trade,
        ILyraGlobals.PricingGlobals memory pricingGlobals,
        uint boardBaseIv
      ) public pure returns (uint, uint) {
        uint orderSize = trade.amount.divideDecimal(pricingGlobals.standardSize);
        uint orderMoveBaseIv = orderSize / 100;
        uint orderMoveSkew = orderMoveBaseIv.multiplyDecimal(pricingGlobals.skewAdjustmentFactor);
        if (trade.isBuy) {
            return (boardBaseIv + (orderMoveBaseIv), listing.skew + (orderMoveSkew));
        } else {
            return (boardBaseIv - (orderMoveBaseIv), listing.skew - (orderMoveSkew));
        }
    }
}
