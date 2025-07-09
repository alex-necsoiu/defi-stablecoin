//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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
 * @notice This contract is the engine of the DSC System. It handles all the logic for the minting and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS (DAI) system.
 */

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

contract DSCEngine is ReentrancyGuard {
       using SafeERC20 for IERC20;
    ///////////////////
    // Errors	     //
    ///////////////////
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenFeedAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    /////////////////////
    // Sate Variables //
    ///////////////////
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10; // 1.0 in 18 decimals, used to determine if the health factor is healthy
    uint256 private constant PRECISION = 1e18; // 1.0 in 18 decimals, used to determine if the health factor is healthy

    mapping(address token => address priceFeed) private s_priceFeeds; // Mapping of token addresses to their price feed addresses
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; // Mapping of user addresses to their collateral deposits
    mapping(address user => uint256 amountDscMinted) private s_dscMinted; // Mapping of user addresses to the amount of DSC minted

    address[] private s_collateralToken; // Array of collateral token addresses

    DecentralizedStableCoin private immutable i_dsc; // The Decentralized Stable Coin contract

    /////////////////////
    // Events 	      //
    ///////////////////
    /**
     * @notice This event is emitted when collateral is deposited by a user.
     * @param user The address of the user who deposited the collateral.
     * @param token The address of the token that was deposited as collateral.
     * @param amount The amount of collateral that was deposited.
     */
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    ///////////////////
    // Modifiers     //
    ///////////////////

    /**
     * @notice This modifier checks if the amount is more than zero.
     * @param amount The amount to check.
     * @dev If the amount is zero, it will revert with the DSCEngine__MustBeMoreThanZero error.
     * @dev This modifier is used to ensure that the amount is more than zero before proceeding with the function execution.
     * @dev This modifier is used in functions that require a non-zero amount, such as depositing collateral or minting DSC.
     * @
     */
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    /**
     * @notice This modifier checks if the token is allowed to be used as collateral.
     * @param token The address of the token to check.
     * @dev If the token is not allowed, it will revert with the DSCEngine__TokenNotAllowed error.
     * @dev This modifier is used in functions that require a valid collateral token, such as depositing collateral or minting DSC.
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

    ///////////////////
    // Functions     //
    ///////////////////
    /**
     * @notice Constructor for the DSCEngine contract.
     * @param tokenAddress An array of addresses of the tokens that can be used as collateral.
     * @param priceFeedAddresses An array of addresses of the price feeds for the tokens.
     * @param dscAddress The address of the Decentralized Stable Coin (DSC) contract.
     * @dev This constructor initializes the DSCEngine contract with the provided token addresses and their corresponding price feed addresses.
     * @dev It also sets the Decentralized Stable Coin (DSC) contract address.
     * @dev The Decentralized Stable Coin (DSC) contract is set as an immutable variable, meaning it cannot be changed after the contract is deployed.
     */
    constructor(address[] memory tokenAddress, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddress.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenFeedAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeeds[tokenAddress[i]] = priceFeedAddresses[i];
            s_collateralToken.push(tokenAddress[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }
    /////////////////////////////
    // External Functions     //
    ///////////////////////////

    function depositCollateralAndMintDsc() external {}

    /**
     * @param tokenCollateralAddress The address of the collateral token to deposit.
     * @param amountCollateral The amount of collateral to deposit.
     * @notice This function allows the user to deposit collateral and mint DSC at the same time
     * @notice The collateral must be approved to this contract before calling this function.
     * @notice The amount of collateral must be more than zero.
     */
    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
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

    /**
     *
     * @param amountDscToMint The amount of DSC to mint.
     * @notice This function allows the user to mint DSC by depositing collateral.
     * @notice The amount of DSC to mint must be more than zero.
     * @notice The user must have enough collateral deposited to cover the health factor.
     * @dev This function calculates the required collateral amount based on the health factor and checks if the user has enough collateral deposited.
     * @dev If the user has enough collateral, it mints the DSC and updates the user's collateral deposits.
     * @dev If the user does not have enough collateral, it reverts with the DSCEngine__BreaksHealthFactor error.
     */

    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorBreaks(msg.sender);
        // Mint DSC to the user
        bool mintSuccess = i_dsc.mint(msg.sender, amountDscToMint);
        if (!mintSuccess) {
            revert DSCEngine__MintFailed();
        }
    }

    function redeemCollateralForDsc() external {}
    function burnDesc() external {}
    function liquidate() external {}

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
    function _getHealthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold =
            (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION; // 50% of the collateral value

        // $150 ETH / 100 DSC = 1.5
        // 150 * 50 = 7500 / 100 = (75 / 100) < 1.0

        //$1000 ETH / 100 DSC = 10
        // 1000 * 50 = 50000 / 100 = (500 / 100) > 1.0
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /**
     * @notice This function calculates the health factor for a user.
     * If health factor is less than 1, the user is at risk of liquidation.
     */
    function _revertIfHealthFactorBreaks(address user) internal view {
        uint256 healthFactor = _getHealthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(healthFactor);
        }
    }

    ///////////////////////////////////////////
    // Public & External View Functions     //
    ///////////////////////////////////////////

    /**
     *  Returns the total collateral value in USD for a given user address.
     * @param user The address of the user to get the collateral value for.
     * @return totalCollateralValueInUsd The total collateral value in USD for the given user address.
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralToken.length; i++) {
            // Get the collateral value from token address
            address token = s_collateralToken[i];
            uint256 collateralAmount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, collateralAmount);
        }
        return totalCollateralValueInUsd;
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
}
