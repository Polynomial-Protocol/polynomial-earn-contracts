// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import { ILiquidityPool } from "../interfaces/lyra/ILiquidityPool.sol";
import { ILyraGlobals } from "../interfaces/lyra/ILyraGlobals.sol";
import { IOptionMarket } from "../interfaces/lyra/IOptionMarket.sol";
import { IOptionMarketViewer } from "../interfaces/lyra/IOptionMarketViewer.sol";
import { SafeDecimalMath } from "../synthetix/SafeDecimalMath.sol";

import { MockSynth } from "./MockSynth.sol";
import { MockOptionViewer } from "./MockOptionViewer.sol";
import { MockOptionMarketPricer } from "./MockOptionMarketPricer.sol";
import "hardhat/console.sol";

contract MockOptionMarket {
    using SafeDecimalMath for uint;

    address owner;
    uint256 public boardCount;
    uint256 listingCount;
    MockSynth UNDERLYING;
    MockSynth PREMIUM_ASSET;
    MockOptionViewer OPTION_VIEWER;
    MockOptionMarketPricer OPTION_PRICER;
    mapping(uint256 => IOptionMarket.OptionBoard) public optionBoards;
    mapping(uint256 => IOptionMarket.OptionListing) public optionListings;
    mapping(uint256 => uint256) premiums;
    mapping(address => mapping(uint256 => uint256)) shortCollateralCall;
    mapping(address => mapping(uint256 => uint256)) shortCollateralPut;
    mapping(uint256 => uint256) public boardToPriceAtExpiry;

    constructor(MockSynth _underlying, MockSynth _premium) {
        owner = msg.sender;
        UNDERLYING = _underlying;
        PREMIUM_ASSET = _premium;
    }

    function createOptionBoard(
        uint expiry,
        uint baseIV,
        uint[] memory strikes,
        uint[] memory skews
    ) external returns (uint) {
        require(msg.sender == owner);

        boardCount++;
        optionBoards[boardCount].id = boardCount;
        optionBoards[boardCount].expiry = expiry;
        optionBoards[boardCount].iv = baseIV;

        for (uint256 i = 0; i < strikes.length; i++) {
            listingCount++;
            optionListings[listingCount] = IOptionMarket.OptionListing(listingCount, strikes[i], skews[i], 0, 0, 0, 0, boardCount);
            optionBoards[boardCount].listingIds.push(listingCount);
        }

        return boardCount;
    }

    function openPosition(
        uint _listingId,
        IOptionMarket.TradeType tradeType,
        uint amount
    ) external returns (uint totalCost) {
        IOptionMarket.OptionListing storage listing = optionListings[_listingId];
        IOptionMarket.OptionBoard storage board = optionBoards[listing.boardId];
        
        ILiquidityPool.Liquidity memory liq;
        bool isBuy = 
            tradeType == IOptionMarket.TradeType.LONG_CALL ||
            tradeType == IOptionMarket.TradeType.LONG_PUT;
        
        IOptionMarket.Trade memory trade = IOptionMarket.Trade({
            isBuy: isBuy,
            amount: amount,
            vol: board.iv.multiplyDecimal(listing.skew),
            expiry: board.expiry,
            liquidity: liq
        });

        ILyraGlobals.PricingGlobals memory _pricingGlobals = OPTION_VIEWER.getPricingGlobals();

        (uint newIv, uint newSkew) = OPTION_PRICER.ivImpactForTrade(
            listing, trade, _pricingGlobals, board.iv
        );

        board.iv = newIv;
        listing.skew = newSkew;
        
        if (tradeType == IOptionMarket.TradeType.SHORT_CALL) {
            totalCost = premiums[_listingId].multiplyDecimal(amount);
            shortCollateralCall[msg.sender][_listingId] += amount;
            require(UNDERLYING.transferFrom(msg.sender, address(this), amount));
            PREMIUM_ASSET.mint(msg.sender, totalCost);
        } else if (tradeType == IOptionMarket.TradeType.SHORT_PUT) {
            shortCollateralPut[msg.sender][_listingId] += amount;
            totalCost = premiums[_listingId].multiplyDecimal(amount);
            require(PREMIUM_ASSET.transferFrom(msg.sender, address(this), amount.multiplyDecimal(listing.strike)));
            PREMIUM_ASSET.mint(msg.sender, totalCost);
        }
    }

    function settleOptions(uint listingId, IOptionMarket.TradeType tradeType) external {
        IOptionMarket.OptionListing memory listing = optionListings[listingId];
        
        uint256 priceAtExpiry = boardToPriceAtExpiry[listing.boardId];

        if (tradeType == IOptionMarket.TradeType.SHORT_CALL) {
            uint256 amount = shortCollateralCall[msg.sender][listingId];
            if (listing.strike > priceAtExpiry) {
                UNDERLYING.transfer(msg.sender, amount);
            } else {
                // console.log(listingId);
                // console.log(listing.strike, priceAtExpiry);
                uint256 ratio = (listing.strike).divideDecimal(priceAtExpiry);
                UNDERLYING.transfer(msg.sender, amount.multiplyDecimal(ratio));
            }
        } else if (tradeType == IOptionMarket.TradeType.SHORT_PUT) {
            uint256 amount = shortCollateralPut[msg.sender][listingId];
            uint256 multiplier = listing.strike < priceAtExpiry ? listing.strike : priceAtExpiry;
            PREMIUM_ASSET.transfer(msg.sender, amount.multiplyDecimal(multiplier));
        }
    }

    function setPremium(uint256 listingId, uint256 premium) external {
        require(msg.sender == owner);

        premiums[listingId] = premium;
    }

    function setExpiryPrice(uint boardId, uint price) external {
        require(msg.sender == owner);

        boardToPriceAtExpiry[boardId] = price;
    }
    
    function setOptionViewer(MockOptionViewer _optionViewer) external {
        require(msg.sender == owner);
        
        OPTION_VIEWER = _optionViewer;
    }

    function setOptionPricer(MockOptionMarketPricer _optionPricer) external {
        require(msg.sender == owner);
        
        OPTION_PRICER = _optionPricer;
    }
    
    function getBoardListings(uint boardId) external view returns (uint[] memory) {
        uint[] memory listingIds = new uint[](optionBoards[boardId].listingIds.length);
        for (uint i = 0; i < optionBoards[boardId].listingIds.length; i++) {
            listingIds[i] = optionBoards[boardId].listingIds[i];
        }
        return listingIds;
    }
    
}