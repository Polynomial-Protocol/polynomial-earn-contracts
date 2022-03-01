// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import { Auth, Authority } from "@rari-capital/solmate/src/auth/Auth.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { FixedPointMathLib } from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";
import { ReentrancyGuard } from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import { IPolynomialShortVol } from "./interfaces/IPolynomialShortVol.sol";

import { IOptionMarket } from "./interfaces/lyra/IOptionMarket.sol";
import { IOptionMarketPricer } from "./interfaces/lyra/IOptionMarketPricer.sol";
import { IOptionMarketViewer } from "./interfaces/lyra/IOptionMarketViewer.sol";
import { ISynthetix } from "./interfaces/lyra/ISynthetix.sol";

import { Pausable } from "./utils/Pausable.sol";

contract PolynomialShortVol is IPolynomialShortVol, ReentrancyGuard, Auth, Pausable {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    /// @notice Number of weeks in a year (in 8 decimals)
    uint256 private constant WEEKS_PER_YEAR = 52142857143;

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------

    /// @notice Underlying Asset
    ERC20 public immutable UNDERLYING;

    /// @notice Collateral Asset
    ERC20 public immutable COLLATERAL;

    /// @notice Lyra Option Market
    IOptionMarket public immutable LYRA_MARKET;

    /// @notice Lyra Option Market Viewer
    IOptionMarketViewer public immutable MARKET_VIEWER;

    /// @notice Synthetix
    ISynthetix public immutable SYNTHETIX;

    /// @notice Synthetix currency key of the underlying token
    bytes32 public immutable SYNTH_KEY_UNDERLYING;

    /// @notice Synthetix currency key of the premium token
    bytes32 public immutable SYNTH_KEY_PREMIUM;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice Human Readable Name of the Vault
    string public name;

    /// @notice Address of the keeper
    address public keeper;

    /// @notice Fee Receipient
    address public feeReceipient;

    /// @notice Current round
    uint256 public currentRound;

    /// @notice Current Listing ID for Call option
    uint256 public currentCallListingId;

    /// @notice Current Listing ID for Put option
    uint256 public currentPutListingId;

    /// @notice Current Listing ID's Expiry
    uint256 public currentExpiry;

    /// @notice Current Listing Strike Price for Call option
    uint256 public currentCallStrike;

    /// @notice Current Listing Strike Price for Put option
    uint256 public currentPutStrike;

    /// @notice Total premium collected in the round
    uint256 public premiumCollected;

    /// @notice Total amount of collateral for the current round
    uint256 public totalFunds;

    /// @notice Funds used so far in the current round
    uint256 public usedFunds;

    /// @notice Total number of options sold in the current round
    uint256 public optionsSold;

    /// @notice Total shares issued so far
    uint256 public totalShares;

    /// @notice Vault capacity
    uint256 public vaultCapacity;

    /// @notice User deposit limit
    uint256 public userDepositLimit;

    /// @notice Total pending deposit amounts (in COLLATERAL)
    uint256 public pendingDeposits;

    /// @notice Pending withdraws (in SHARES)
    uint256 public pendingWithdraws;

    /// @notice IV Slippage limit per trade
    uint256 public ivLimit;

    /// @notice Performance Fee
    uint256 public performanceFee;

    /// @notice Management Fee
    uint256 public managementFee;

    /// @notice Mapping of User Info
    mapping (address => UserInfo) public userInfos;

    /// @notice Mapping of round versus perfomance index
    mapping (uint256 => uint256) public performanceIndices;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event StartNewRound(uint256 indexed round, uint256 indexed callListingId, uint256 indexed putListingId, uint256 newIndex);

    event SellOptions(uint256 indexed round, uint256 optionsSold, uint256 totalCost);

    event CompleteWithdraw(address indexed user, uint256 indexed withdrawnRound, uint256 shares, uint256 funds);

    event Deposit(address indexed user, uint256 indexed depositRound, uint256 amt);

    event RequestWithdraw(address indexed user, uint256 indexed withdrawnRound, uint256 shares);

    event CancelWithdraw(address indexed user, uint256 indexed withdrawnRound, uint256 shares);

    event SetCap(address indexed auth, uint256 oldCap, uint256 newCap);

    event SetUserDepositLimit(address indexed auth, uint256 oldDepositLimit, uint256 newDepositLimit);

    event SetIvLimit(address indexed auth, uint256 oldLimit, uint256 newLimit);

    event SetFees(address indexed auth, uint256 oldManageFee, uint256 oldPerfFee, uint256 newManageFee, uint256 newPerfFee);

    event SetFeeReceipient(address indexed auth, address oldReceipient, address newReceipient);

    event SetKeeper(address indexed auth, address oldKeeper, address newKeeper);

    /// -----------------------------------------------------------------------
    /// Modifiers
    /// -----------------------------------------------------------------------

    modifier onlyKeeper {
        require(msg.sender == keeper, "NOT_KEEPER");
        _;
    }

    constructor(
        string memory _name,
        ERC20 _underlying,
        ERC20 _collateral,
        IOptionMarket _lyraMarket,
        IOptionMarketViewer _marketViewer,
        ISynthetix _synthetix,
        bytes32 _underlyingKey,
        bytes32 _premiumKey
    ) Auth(msg.sender, Authority(address(0x0))) {
        name = _name;
        UNDERLYING = _underlying;
        COLLATERAL = _collateral;
        LYRA_MARKET = _lyraMarket;
        MARKET_VIEWER = _marketViewer;
        SYNTHETIX = _synthetix;
        SYNTH_KEY_UNDERLYING = _underlyingKey;
        SYNTH_KEY_PREMIUM = _premiumKey;

        performanceIndices[0] = 1e18;
    }

    /// -----------------------------------------------------------------------
    /// User actions
    /// -----------------------------------------------------------------------

    function deposit(uint256 _amt) external override {
        require(_amt > 0, "AMT_CANNOT_BE_ZERO");
        require(_amt <= userDepositLimit, "USER_DEPOSIT_LIMIT_EXCEEDED");

        if (currentRound == 0) {
            _depositForRoundZero(msg.sender, _amt);
        } else {
            _deposit(msg.sender, _amt);
        }

        emit Deposit(msg.sender, currentRound, _amt);
    }

    function deposit(address _user, uint256 _amt) external override {
        require(_amt > 0, "AMT_CANNOT_BE_ZERO");
        require(_amt <= userDepositLimit, "USER_DEPOSIT_LIMIT_EXCEEDED");

        if (currentRound == 0) {
            _depositForRoundZero(_user, _amt);
        } else {
            _deposit(_user, _amt);
        }

        emit Deposit(_user, currentRound, _amt);
    }

    function requestWithdraw(uint256 _shares) external override {
        UserInfo storage userInfo = userInfos[msg.sender];

        require(userInfo.totalShares >= _shares, "INSUFFICIENT_SHARES");

        if (currentRound == 0) {
            COLLATERAL.safeTransfer(msg.sender, _shares);
            totalShares -= _shares;
        } else {
            if (userInfo.withdrawRound < currentRound) {
                require(userInfo.withdrawnShares == 0, "INCOMPLETE_PENDING_WITHDRAW");
            }
            userInfo.withdrawRound = currentRound;
            userInfo.withdrawnShares += _shares;
            pendingWithdraws += _shares;
        }
        userInfo.totalShares -= _shares;

        emit RequestWithdraw(msg.sender, currentRound, _shares);
    }

    function completeWithdraw() external override {
        UserInfo storage userInfo = userInfos[msg.sender];

        require(currentRound > userInfo.withdrawRound, "ROUND_NOT_OVER");

        uint256 pendingWithdrawAmount = userInfo.withdrawnShares.fmul(performanceIndices[userInfo.withdrawRound], 1e18);
        COLLATERAL.safeTransfer(msg.sender, pendingWithdrawAmount);

        emit CompleteWithdraw(msg.sender, userInfo.withdrawRound, userInfo.withdrawnShares, pendingWithdrawAmount);

        userInfo.withdrawnShares = 0;
        userInfo.withdrawRound = 0;
    }

    function cancelWithdraw(uint256 _shares) external override {
        UserInfo storage userInfo = userInfos[msg.sender];

        require(userInfo.withdrawnShares >= _shares, "NO_WITHDRAW_REQUESTS");
        require(userInfo.withdrawRound == currentRound, "CANNOT_CANCEL_AFTER_ROUND");

        userInfo.withdrawnShares -= _shares;
        pendingWithdraws -= _shares;
        userInfo.totalShares += _shares;

        emit CancelWithdraw(msg.sender, currentRound, _shares);
    }

    /// -----------------------------------------------------------------------
    /// Owner actions
    /// -----------------------------------------------------------------------

    function setCap(uint256 _newCap) external requiresAuth {
        require(_newCap > 0, "CAP_CANNOT_BE_ZERO");
        emit SetCap(msg.sender, vaultCapacity, _newCap);
        vaultCapacity = _newCap;
    }

    function setUserDepositLimit(uint256 _depositLimit) external requiresAuth {
        require(_depositLimit > 0, "LIMIT_CANNOT_BE_ZERO");
        emit SetUserDepositLimit(msg.sender, userDepositLimit, _depositLimit);
        userDepositLimit = _depositLimit;
    }

    function setIvLimit(uint256 _ivLimit) external requiresAuth {
        require(_ivLimit > 0, "SLIPPAGE_CANNOT_BE_ZERO");
        emit SetIvLimit(msg.sender, ivLimit, _ivLimit);
        ivLimit = _ivLimit;
    }

    function setFees(uint256 _perfomanceFee, uint256 _managementFee) external requiresAuth {
        require(_perfomanceFee <= 1e7, "PERF_FEE_TOO_HIGH");
        require(_managementFee <= 5e6, "MANAGE_FEE_TOO_HIGH");

        emit SetFees(msg.sender, managementFee, performanceFee, _managementFee, _perfomanceFee);

        performanceFee = _perfomanceFee;
        managementFee = _managementFee;
    }

    function setFeeReceipient(address _feeReceipient) external requiresAuth {
        require(_feeReceipient != address(0x0), "CANNOT_BE_VOID");
        emit SetFeeReceipient(msg.sender, feeReceipient, _feeReceipient);
        feeReceipient = _feeReceipient;
    }

    function setKeeper(address _keeper) external requiresAuth {
        require(_keeper != address(0x0), "CANNOT_BE_VOID");
        emit SetKeeper(msg.sender, keeper, _keeper);
        keeper = _keeper;
    }

    function startNewRound(uint256 _callListingId, uint256 _putListingId) external requiresAuth nonReentrant {
        (,uint256 callStrikePrice,,,,,, uint256 callBoardId) = LYRA_MARKET.optionListings(_callListingId);
        (,uint256 putStrikePrice,,,,,, uint256 putBoardId) = LYRA_MARKET.optionListings(_putListingId);
        require(callBoardId == putBoardId, "BOARD_ID_MISMATCH");
        (, uint256 expiry,,) = LYRA_MARKET.optionBoards(putBoardId);
        require(expiry >= block.timestamp, "INVALID_LISTING_ID");
        require(block.timestamp > currentExpiry, "ROUND_NOT_OVER");

        uint256 newIndex = 1e18;

        if (currentRound > 0) {
            uint256 totalFees;
            (,,,,,,, uint256 boardId) = LYRA_MARKET.optionListings(currentCallListingId);
            uint256 expiryPrice = LYRA_MARKET.boardToPriceAtExpiry(boardId);

            uint256 preSettleUnderBal = UNDERLYING.balanceOf(address(this));
            LYRA_MARKET.settleOptions(currentPutListingId, IOptionMarket.TradeType.SHORT_PUT);
            LYRA_MARKET.settleOptions(currentCallListingId, IOptionMarket.TradeType.SHORT_CALL);
            uint256 postSettleUnderBal = UNDERLYING.balanceOf(address(this));

            SYNTHETIX.exchange(SYNTH_KEY_UNDERLYING, postSettleUnderBal - preSettleUnderBal, SYNTH_KEY_PREMIUM);

            uint256 totalCollateralBal = COLLATERAL.balanceOf(address(this)) - pendingDeposits;

            if (expiryPrice > currentPutStrike && expiryPrice < currentCallStrike) {
                uint256 currentRoundManagementFees = totalCollateralBal.fmul(managementFee, WEEKS_PER_YEAR);
                uint256 currentRoundPerfomanceFee = premiumCollected.fmul(performanceFee, WEEKS_PER_YEAR);
                totalFees = currentRoundManagementFees + currentRoundPerfomanceFee;
                COLLATERAL.safeTransfer(feeReceipient, totalFees);
            }

            uint256 deployableFunds = totalCollateralBal + premiumCollected - totalFees;
            newIndex = deployableFunds.fdiv(totalShares, 1e18);
            performanceIndices[currentRound] = newIndex;

            totalShares += pendingDeposits.fdiv(newIndex, 1e18);
            totalShares -= pendingWithdraws;

            uint256 fundsPendingWithdraws = pendingWithdraws.fmul(newIndex, 1e18);
            totalFunds = deployableFunds + pendingDeposits - fundsPendingWithdraws;
            
            pendingDeposits = 0;
            pendingWithdraws = 0;
            usedFunds = 0;
            premiumCollected = 0;
            optionsSold = 0;
        } else {
            totalFunds = COLLATERAL.balanceOf(address(this));
        }

        emit StartNewRound(currentRound + 1, _callListingId, _putListingId, newIndex);

        currentRound++;
        currentCallListingId = _callListingId;
        currentCallStrike = callStrikePrice;
        currentPutListingId = _putListingId;
        currentPutStrike = putStrikePrice;
        currentExpiry = expiry;
    }

    function sellOptions(uint256 _susdAmt) external onlyKeeper nonReentrant whenNotPaused {
        require(_susdAmt > 0, "INVALID_AMT");

        uint256 optionsToSell = SYNTHETIX.exchange(SYNTH_KEY_PREMIUM, _susdAmt, SYNTH_KEY_UNDERLYING);
        uint256 amtForPutCollateral = optionsToSell.fmul(currentPutStrike, 1e18);

        require(amtForPutCollateral + _susdAmt <= totalFunds - usedFunds, "INSUFFICIENT_AMT");

        IOptionMarketViewer.TradePremiumView memory zeroTradePremium;
        IOptionMarketViewer.TradePremiumView memory tradePremium;
        IOptionMarket.TradeType tradeType = IOptionMarket.TradeType.SHORT_CALL;

        zeroTradePremium = MARKET_VIEWER.getPremiumForOpen(currentCallListingId, tradeType, 0);
        tradePremium = MARKET_VIEWER.getPremiumForOpen(currentCallListingId, tradeType, optionsToSell);

        require(zeroTradePremium.newIv - tradePremium.newIv < ivLimit / 2, "IV_LIMIT_HIT");

        UNDERLYING.safeApprove(address(LYRA_MARKET), optionsToSell);
        uint256 callPremiumReceived = LYRA_MARKET.openPosition(currentCallListingId, tradeType, optionsToSell);

        tradeType = IOptionMarket.TradeType.SHORT_PUT;

        zeroTradePremium = MARKET_VIEWER.getPremiumForOpen(currentPutListingId, tradeType, 0);
        tradePremium = MARKET_VIEWER.getPremiumForOpen(currentPutListingId, tradeType, optionsToSell);

        require(zeroTradePremium.newIv - tradePremium.newIv < ivLimit / 2, "IV_LIMIT_HIT");

        COLLATERAL.safeApprove(address(LYRA_MARKET), amtForPutCollateral);
        uint256 putPremiumReceived = LYRA_MARKET.openPosition(currentPutListingId, tradeType, optionsToSell);

        uint256 totalPremiumReceived = callPremiumReceived + putPremiumReceived;

        premiumCollected += totalPremiumReceived;
        usedFunds += amtForPutCollateral + _susdAmt;
        optionsSold += optionsToSell;

        emit SellOptions(currentRound, optionsToSell, totalPremiumReceived);
    }

    /// -----------------------------------------------------------------------
    /// Internal Methods
    /// -----------------------------------------------------------------------

    function _depositForRoundZero(address _user, uint256 _amt) internal {
        COLLATERAL.safeTransferFrom(msg.sender, address(this), _amt);
        require(COLLATERAL.balanceOf(address(this)) <= vaultCapacity, "CAPACITY_EXCEEDED");

        UserInfo storage userInfo = userInfos[_user];
        userInfo.totalShares += _amt;
        totalShares += _amt;
    }

    function _deposit(address _user, uint256 _amt) internal {
        COLLATERAL.safeTransferFrom(msg.sender, address(this), _amt);

        pendingDeposits += _amt;
        require(totalFunds + pendingDeposits < vaultCapacity, "CAPACITY_EXCEEDED");

        UserInfo storage userInfo = userInfos[_user];
        if (userInfo.depositRound > 0 && userInfo.depositRound < currentRound) {
            userInfo.totalShares = userInfo.pendingDeposit.fdiv(performanceIndices[userInfo.depositRound], 1e18);
            userInfo.pendingDeposit = _amt;
        } else {
            userInfo.pendingDeposit += _amt;
        }
        userInfo.depositRound = currentRound;
    }
}