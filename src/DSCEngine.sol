// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// ─────────────────────────────────────────────────────────────────────────────
// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
//                            IMPORTS
// ─────────────────────────────────────────────────────────────────────────────

import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// ─────────────────────────────────────────────────────────────────────────────
// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
//                            CONTRACT
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @title Decentralized Stable Coin Engine
 * @author Alex Necsoiu
 * @notice Core engine for the DSC system, responsible for minting, redeeming, collateral management, and liquidation logic.
 * @dev Inspired by MakerDAO's DSS (DAI) system. Designed for minimalism, security, and extensibility.
 * 
 * Key Properties:
 * - Exogenous Collateral: ETH & BTC
 * - Dollar Pegged: 1 DSC ≈ $1.00
 * - Algorithmically Maintained Stability
 * - No governance, no fees, only WETH and WBTC as collateral
 */
contract DSCEngine is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─────────────────────────────────────────────────────────────────────────
    // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
    //                                ERRORS
    // ─────────────────────────────────────────────────────────────────────────

    error DSCEngine__TokenFeedAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__NeedsMoreThanZero();

    // ─────────────────────────────────────────────────────────────────────────
    // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
    //                           STATE VARIABLES
    // ─────────────────────────────────────────────────────────────────────────

    // --- Protocol Constants ---
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% over-collateralization required
    uint256 private constant LIQUIDATION_BONUS = 10;     // 10% bonus for liquidators
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;   // Minimum health factor before liquidation
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10; // Used to normalize Chainlink price feeds to 18 decimals
    uint256 private constant PRECISION = 1e18;           // Standard precision for calculations

    // --- Storage ---
    mapping(address token => address priceFeed) private s_priceFeeds; // Collateral token => price feed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; // User => token => amount
    mapping(address user => uint256 amountDscMinted) private s_dscMinted; // User => DSC minted

    address[] private s_collateralTokens; // List of all accepted collateral tokens

    DecentralizedStableCoin private immutable i_dsc; // DSC token contract

    // ─────────────────────────────────────────────────────────────────────────
    // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
    //                                 EVENTS
    // ─────────────────────────────────────────────────────────────────────────

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount);

    // ─────────────────────────────────────────────────────────────────────────
    // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
    //                                MODIFIERS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Ensures the provided amount is greater than zero.
     * @param amount The amount to validate.
     */
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    /**
     * @notice Ensures the token is allowed as collateral.
     * @param token The token address to check.
     */
    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
    //                              CONSTRUCTOR
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Initializes the DSCEngine contract with supported collateral and price feeds.
     * @param tokenAddress Array of collateral token addresses.
     * @param priceFeedAddresses Array of corresponding Chainlink price feed addresses.
     * @param dscAddress Address of the Decentralized Stable Coin (DSC) contract.
     */
    constructor(address[] memory tokenAddress, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddress.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenFeedAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeeds[tokenAddress[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddress[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
    //                        EXTERNAL & PUBLIC FUNCTIONS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Deposit collateral and mint DSC in a single transaction.
     * @param tokenCollateralAddress ERC20 token address to deposit as collateral.
     * @param amountCollateral Amount of collateral to deposit.
     * @param amountDscToMint Amount of DSC to mint.
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    )
        external
    {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice Redeem collateral and burn DSC in a single transaction.
     * @param tokenCollateralAddress ERC20 token address to redeem.
     * @param amountCollateral Amount of collateral to redeem.
     * @param amountDscToBurn Amount of DSC to burn.
     */
    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Redeem collateral. User must have no DSC minted.
     * @param tokenCollateralAddress ERC20 token address to redeem.
     * @param amountCollateral Amount of collateral to redeem.
     */
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Burn DSC to reduce debt and improve health factor.
     * @param amount Amount of DSC to burn.
     */
    function burnDsc(uint256 amount) external moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Liquidate an undercollateralized user.
     * @param collateral Collateral token address to seize.
     * @param user Address of the user to liquidate.
     * @param debtToCover Amount of DSC to burn to cover user's debt.
     * @dev Liquidator receives collateral at a discount (LIQUIDATION_BONUS).
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    )
        external
        isAllowedToken(collateral)
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        _redeemCollateral(collateral, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Mint DSC against deposited collateral.
     * @param amountDscToMint Amount of DSC to mint.
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * @notice Deposit collateral to the protocol.
     * @param tokenCollateralAddress ERC20 token address to deposit.
     * @param amountCollateral Amount of collateral to deposit.
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        IERC20(tokenCollateralAddress).safeTransferFrom(msg.sender, address(this), amountCollateral);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
    //                        PRIVATE & INTERNAL FUNCTIONS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Internal: Redeem collateral for a user.
     * @param tokenCollateralAddress Collateral token address.
     * @param amountCollateral Amount to redeem.
     * @param from Address to deduct collateral from.
     * @param to Address to send collateral to.
     */
    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    )
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        IERC20(tokenCollateralAddress).safeTransfer(to, amountCollateral);
    }

    /**
     * @notice Internal: Burn DSC for a user.
     * @param amountDscToBurn Amount of DSC to burn.
     * @param onBehalfOf User whose debt is reduced.
     * @param dscFrom Address from which DSC is transferred and burned.
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_dscMinted[onBehalfOf] -= amountDscToBurn;
        IERC20(address(i_dsc)).safeTransferFrom(dscFrom, address(this), amountDscToBurn);
        i_dsc.burn(amountDscToBurn);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
    //                  PRIVATE & INTERNAL VIEW / PURE FUNCTIONS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Internal: Get account info for a user.
     * @param user Address to query.
     * @return totalDscMinted Amount of DSC minted by user.
     * @return totalCollateralValueInUsd Total collateral value in USD.
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        totalCollateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @notice Internal: Calculate health factor for a user.
     * @param user Address to check.
     * @return Health factor (scaled by 1e18).
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    /**
     * @notice Internal: Get USD value of a token amount using Chainlink price feed.
     * @param token Token address.
     * @param amount Amount of tokens.
     * @return USD value (18 decimals).
     */
    function _getUsdValue(address token, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /**
     * @notice Internal: Calculate health factor from DSC minted and collateral value.
     * @param totalDscMinted Amount of DSC minted.
     * @param collateralValueInUsd Collateral value in USD.
     * @return Health factor (scaled by 1e18).
     */
    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    )
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /**
     * @notice Internal: Revert if user's health factor is below minimum.
     * @param user Address to check.
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
    //                  PUBLIC & EXTERNAL VIEW / PURE FUNCTIONS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice External: Calculate health factor from DSC minted and collateral value.
     * @param totalDscMinted Amount of DSC minted.
     * @param collateralValueInUsd Collateral value in USD.
     * @return Health factor (scaled by 1e18).
     */
    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    )
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    /**
     * @notice External: Get account info for a user.
     * @param user Address to query.
     * @return totalDscMinted Amount of DSC minted by user.
     * @return collateralValueInUsd Total collateral value in USD.
     */
    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    /**
     * @notice External: Get USD value of a token amount using Chainlink price feed.
     * @param token Token address.
     * @param amount Amount of tokens.
     * @return USD value (18 decimals).
     */
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /**
     * @notice External: Get user's collateral balance for a specific token.
     * @param user Address to query.
     * @param token Collateral token address.
     * @return Amount of collateral deposited.
     */
    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    /**
     * @notice External: Get total collateral value in USD for a user.
     * @param user Address to query.
     * @return totalCollateralValueInUsd Total collateral value in USD.
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 collateralAmount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, collateralAmount);
        }
        return totalCollateralValueInUsd;
    }

    /**
     * @notice External: Get token amount equivalent to a USD amount.
     * @param token Token address.
     * @param usdAmountInWei USD amount in wei.
     * @return Amount of tokens equivalent to the given USD amount.
     */
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
    //                             GETTERS
    // ─────────────────────────────────────────────────────────────────────────

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }
}
