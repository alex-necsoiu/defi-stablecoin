//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title Decentralized Stable Coin Engine
 * @author Alex Necsoiu
 *
 * The system is designed to to be as minimal as possible, and have the tokens maintain a 1 token == $1.00 USD peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral: Backed by ETH and BTC.
 * - Dollar Pegged: The stablecoin is pegged to the US Dollar.
 * - Algorithmically Stable
 * It is similar to DAI if DAI had no governance, no fees, and only backed by WETH and WBTC.
 *
 * @notice This contract is the engine of the DSC System. It handles all the logic for the minting and redeeming DSC, as
 * well as depositing & withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS (DAI) system.
 */


contract DSCEngine is ReentrancyGuard {
    using SafeERC20 for IERC20;
    ///////////////////
    // Errors	     //
    ///////////////////

    error DSCEngine__TokenFeedAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__NeedsMoreThanZero();

    /////////////////////
    // Sate Variables //
    ///////////////////
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10; // 1.0 in 18 decimals, used to determine if the health
        // factor is healthy
    uint256 private constant PRECISION = 1e18; // 1.0 in 18 decimals, used to determine if the health factor is healthy

    mapping(address token => address priceFeed) private s_priceFeeds; // Mapping of token addresses to their price feed
        // addresses
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; // Mapping of user
        // addresses to their collateral deposits
    mapping(address user => uint256 amountDscMinted) private s_dscMinted; // Mapping of user addresses to the amount of
        // DSC minted

    address[] private s_collateralTokens; // Array of collateral token addresses

    DecentralizedStableCoin private immutable i_dsc; // The Decentralized Stable Coin contract

    /////////////////////
    // Events 	      //
    ///////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount);

    ///////////////////
    // Modifiers     //
    ///////////////////

    /**
     * @notice This modifier checks if the amount is more than zero.
     * @param amount The amount to check.
     * @dev If the amount is zero, it will revert with the DSCEngine__MustBeMoreThanZero error.
     * @dev This modifier is used to ensure that the amount is more than zero before proceeding with the function
     * execution.
     * @
     */
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    /**
     * @notice This modifier checks if the token is allowed to be used as collateral.
     * @param token The address of the token to check.
     * @dev If the token is not allowed, it will revert with the DSCEngine__TokenNotAllowed error.
     * @dev This modifier is used in functions that require a valid collateral token, such as depositing collateral or
     * minting DSC.
     */
    modifier isAllowedToken(address token) {
        // This modifier will check if the token is allowed to be used as collateral
        // It will check against a list of allowed tokens
        // If the token is not allowed, it will revert with an error
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    //////////////////////
    // Constructor     //
    ////////////////////
    /**
     * @notice Constructor for the DSCEngine contract.
     * @param tokenAddress An array of addresses of the tokens that can be used as collateral.
     * @param priceFeedAddresses An array of addresses of the price feeds for the tokens.
     * @param dscAddress The address of the Decentralized Stable Coin (DSC) contract.
     * @dev This constructor initializes the DSCEngine contract with the provided token addresses and their
     * corresponding price feed addresses.
     * @dev It also sets the Decentralized Stable Coin (DSC) contract address.
     * @dev The Decentralized Stable Coin (DSC) contract is set as an immutable variable, meaning it cannot be changed
     * after the contract is deployed.
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
    /////////////////////////////
    // External Functions     //
    ///////////////////////////

    /**
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountDscToMint: The amount of DSC you want to mint
     * @notice This function will deposit your collateral and mint DSC in one transaction
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
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're withdrawing
     * @param amountCollateral: The amount of collateral you're withdrawing
     * @param amountDscToBurn: The amount of DSC you want to burn
     * @notice This function will withdraw your collateral and burn DSC in one transaction
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
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're redeeming
     * @param amountCollateral: The amount of collateral you're redeeming
     * @notice This function will redeem your collateral.
     * @notice If you have DSC minted, you will not be able to redeem until you burn your DSC
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

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_dscMinted[onBehalfOf] -= amountDscToBurn;

        IERC20(address(i_dsc)).safeTransferFrom(dscFrom, address(this), amountDscToBurn);
        i_dsc.burn(amountDscToBurn);
    }

    /*
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
    * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this
    to work.
    * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate
    anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
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
        // If covering 100 DSC, we need to $100 of collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // And give them a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        // Burn DSC equal to debtToCover
        // Figure out how much collateral to recover based on how much burnt
        _redeemCollateral(collateral, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        // This conditional should never hit, but just in case
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////
    // Public Functions
    ///////////////////
    /*
     * @param amountDscToMint: The amount of DSC you want to mint
     * You can only mint DSC if you have enough collateral
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);

        if (minted != true) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * @param tokenCollateralAddress The address of the collateral token to deposit.
     * @param amountCollateral The amount of collateral to deposit.
     * @notice This function allows the user to deposit collateral and mint DSC at the same time
     * @notice The collateral must be approved to this contract before calling this function.
     * @notice The amount of collateral must be more than zero.
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

    ///////////////////////////////////////////
    // Private & Internal View Functions     //
    ///////////////////////////////////////////

    /**
     * @notice This function gets the account information for a user.
     * @param user The address of the user to get the account information for.
     * @return totalDscMinted The total amount of DSC minted by the user.
     * @return totalCollateralValueInUsd The total collateral value in USD for the user.
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
     * Returns how close to the liquidation threshold the user is.
     * If the health factor is less than 1, the user is at risk of liquidation.
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    // function _getHealthFactor(address user) private view returns (uint256) {
    //     (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = _getAccountInformation(user);
    //     uint256 collateralAdjustedForThreshold =
    //         (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION; // 50% of the collateral
    // value

    //     // $150 ETH / 100 DSC = 1.5
    //     // 150 * 50 = 7500 / 100 = (75 / 100) < 1.0

    //     //$1000 ETH / 100 DSC = 10
    //     // 1000 * 50 = 50000 / 100 = (500 / 100) > 1.0
    //     return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    // }

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
     * @notice This function calculates the health factor for a user.
     * If health factor is less than 1, the user is at risk of liquidation.
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /**
     * @notice This function redeems collateral for a user.
     * @param tokenCollateralAddress The address of the collateral token to redeem.
     * @param amountCollateral The amount of collateral to redeem.
     * @param from The address of the user redeeming the collateral.
     * @param to The address to send the redeemed collateral to.
     * @dev This function updates the user's collateral balance, emits an event, and transfers the collateral to the
     * specified address.
     * @dev It is called internally by the redeemCollateral and redeemCollateralForDsc functions.
     * @dev The function checks if the user has enough collateral to redeem.
     * @dev If the user does not have enough collateral, it will revert with an error.
     * @dev The function uses SafeERC20 to safely transfer the collateral token to the< specified address.
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

    ///////////////////////////////////////////
    // Public & External View Functions     //
    ///////////////////////////////////////////
    /**
     * @notice This function is used to check how much collateral a user has deposited for a specific token.
     * @param user The address of the user to get the DSC minted for.
     * @param token The address of the collateral token to check.
     * @return The amount of collateral deposited by the user for the specified token.
     */
    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }
    /**
     *  Returns the total collateral value in USD for a given user address.
     * @param user The address of the user to get the collateral value for.
     * @return totalCollateralValueInUsd The total collateral value in USD for the given user address.
     */

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            // Get the collateral value from token address
            address token = s_collateralTokens[i];
            uint256 collateralAmount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, collateralAmount);
        }
        return totalCollateralValueInUsd;
    }

    /**
     * @notice This function returns the amount of tokens that can be obtained from a given USD amount.
     * @param token The address of the token to get the amount for.
     * @param usdAmountInWei The USD amount in wei to convert to token amount.
     * @return The amount of tokens that can be obtained from the given USD amount.
     * @dev This function uses the Chainlink price feed to get the latest price of the token.
     * @dev It assumes that the price feed returns a value with 8 decimals places.
     */
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData(); // Return 8 decimals places
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    /**
     * @notice This function returns the USD value of a given token amount.
     * @param token The address of the token to get the USD value for.
     * @param amount The amount of the token to get the USD value for.
     * @return The USD value of the given token amount.
     * @dev This function uses the Chainlink price feed to get the latest price of the
     *
     */
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        // 0x694AA1769357215DE4FAC081bf1f309aDC325306 ETH/USD price feed address Sepolia Testnet
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData(); // Return 8 decimals places
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; // (1000 * 1e8 * 1e10) * 1000 * 1e18
    }

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
