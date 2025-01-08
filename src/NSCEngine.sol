// SPDX-License-Identifier: MIT

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
pragma solidity ^0.8.27;

import {NexusStableCoin} from "./NexusStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
/**
 * @title NSCEngine
 * @author Luciano Zanin Gabriel
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar pegged
 * - Algoritmically stable
 *
 * It is similar to DAI, but with a few key differences:
 * - No governance
 * - No fees
 * - Only backed by WETH and WBTC
 *
 * Our NSC system should always be over-collateralized. This means that the total value of the collateral should always be greater than the total value of the NSC.
 *
 * @notice This contract is the core of the NSC System. It handles all the logic for minting and burning NSC, as well asa depositing and withdrawing collateral.
 * @notice This contract is loosely based on the MakerDAO DSS system.
 */

contract NSCEngine is ReentrancyGuard {
    ////////////////////////
    /////// Errors /////////
    ////////////////////////
    error NSCEngine__NeedsMoreThanZero();
    error NSCEngine__TokenAddressesAndPriceFeedAddressesMustBeOfEqualLength();
    error NSCEngine__NotAllowedToken();
    error NSCEngine__TransferFailed();
    error NSCEngine__MintFailed();
    error NSCEngine__BurnAmountExceedsBalance();
    error NSCEngine__HealthFactorIsBroken(uint256 healthFactor);
    error NSCEngine__HealthFactorOk();
    error NSCEngine__HealthFactorNotImproved();

    ////////////////////////
    /////// Types /////////
    ////////////////////////
    using OracleLib for AggregatorV3Interface;

    ////////////////////////
    /////// State /////////
    ////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountNscMinted) private s_nscMinted;
    address[] private s_collateralTokens;

    NexusStableCoin private immutable i_nsc;

    ////////////////////////
    /////// Modifiers //////
    ////////////////////////
    modifier moreThanZero(uint256 value) {
        if (value == 0) revert NSCEngine__NeedsMoreThanZero();
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert NSCEngine__NotAllowedToken();
        }
        _;
    }

    ////////////////////////
    /////// Events /////////
    ////////////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );
    event NSCBurned(address indexed burner, uint256 indexed amount);

    ////////////////////////
    /////// Functions //////
    ////////////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address nscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert NSCEngine__TokenAddressesAndPriceFeedAddressesMustBeOfEqualLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_nsc = NexusStableCoin(nscAddress);
    }

    ////////////////////////
    /////// External ///////
    ////////////////////////

    /**
     * @notice Deposit collateral and mint NSC in one transaction.
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountNscToMint The amount of NSC to mint
     */
    function depositCollateralAndMint(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountNscToMint)
        external
    {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintNSC(amountNscToMint);
    }

    /**
     * @notice Deposit collateral into the protocol following CEI pattern.
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert NSCEngine__TransferFailed();
        }
    }

    /**
     * @notice Allow user to redeem collateral for NSC in one transaction.
     * @param tokenCollateralAddress The address of the token to redeem as collateral
     * @param amountCollateral The amount of collateral to redeem
     * @param amountNscToBurn The amount of NSC to burn
     */
    function redeemCollateralForNSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountNscToBurn)
        external
        moreThanZero(amountCollateral)
        moreThanZero(amountNscToBurn)
        isAllowedToken(tokenCollateralAddress)
    {
        burnNSC(amountNscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender, false);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Mint NSC following CEI pattern.
     * @param amountNscToMint The amount of NSC to mint.
     * @notice They must have more collateral value than the minimum threshold.
     */
    function mintNSC(uint256 amountNscToMint) public moreThanZero(amountNscToMint) nonReentrant {
        s_nscMinted[msg.sender] += amountNscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool success = i_nsc.mint(msg.sender, amountNscToMint);
        if (!success) {
            revert NSCEngine__MintFailed();
        }
    }

    /**
     * @notice Burn NSC tokens from the caller.
     * @param amount The amount of NSC to burn.
     */
    function burnNSC(uint256 amount) public moreThanZero(amount) nonReentrant {
        _burnNSC(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 healthFactorBeforeLiquidation = _healthFactor(user);
        if (healthFactorBeforeLiquidation > MIN_HEALTH_FACTOR) {
            revert NSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonus = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 amountCollateralToSeize = tokenAmountFromDebtCovered + bonus;
        _redeemCollateral(collateral, amountCollateralToSeize, user, msg.sender, true);

        _burnNSC(debtToCover, user, msg.sender);

        s_collateralDeposited[user][collateral] -= amountCollateralToSeize;
        s_collateralDeposited[msg.sender][collateral] += amountCollateralToSeize;

        uint256 healthFactorAfterLiquidation = _healthFactor(user);
        if (healthFactorAfterLiquidation <= healthFactorBeforeLiquidation) {
            revert NSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view returns (uint256) {
        return _healthFactor(msg.sender);
    }

    /////////////////////////////////
    /////// Private & Internal view /////
    ////////////////////////////////
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalNscMinted, uint256 totalCollateralValueInUsd)
    {
        totalNscMinted = s_nscMinted[user];
        totalCollateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * Returns how close to liquidation a user is.
     * The closer to 1, the more collateral the user has compared to their debt.
     * The closer to 0, the more debt the user has compared to their collateral.
     * If the health factor is less than 1, the user is liquidatable.
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalNscMinted, uint256 totalCollateralValueInUsd) = _getAccountInformation(user);
        if (totalNscMinted == 0) {
            return type(uint256).max;
        }
        uint256 collateralAdjustedForThreshold =
            (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION_FACTOR) / totalNscMinted;
    }

    /**
     * @notice Revert if the health factor is broken.
     * @param user The address of the user.
     */
    function _revertIfHealthFactorIsBroken(address user) private view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert NSCEngine__HealthFactorIsBroken(userHealthFactor);
        }
    }

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to,
        bool addCollateralTo
    ) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        if (addCollateralTo) {
            s_collateralDeposited[to][tokenCollateralAddress] += amountCollateral;
        }
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert NSCEngine__TransferFailed();
        }
    }

    /**
     * @dev Internal function to handle the burning of NSC tokens.
     * @param amount The amount of NSC to burn.
     * @param onBehalfOf The address of the user whose NSC is being burned.
     * @param from The address of the user whose NSC is being burned.
     */
    function _burnNSC(uint256 amount, address onBehalfOf, address from) private {
        if (i_nsc.balanceOf(onBehalfOf) < amount) {
            revert NSCEngine__BurnAmountExceedsBalance();
        }
        s_nscMinted[onBehalfOf] -= amount;
        emit NSCBurned(onBehalfOf, amount);

        bool success = i_nsc.transferFrom(from, address(this), amount);
        if (!success) {
            revert NSCEngine__TransferFailed();
        }
        i_nsc.burn(amount);
    }

    ////////////////////////////////////////////////
    /////// Public & External view functions ///////
    ////////////////////////////////////////////////
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION_FACTOR;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (usdAmountInWei * PRECISION_FACTOR) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getCollateralTokens() public view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalNscMinted, uint256 totalCollateralValueInUsd)
    {
        (totalNscMinted, totalCollateralValueInUsd) = _getAccountInformation(user);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getNscAddress() external view returns (address) {
        return address(i_nsc);
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION_FACTOR;
    }
}
