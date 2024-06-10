// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

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

/**
 * @author Gurkirat
 *
 * The system is designed so that stablecoin is pegged to USD at $1.00
 *
 * It is similar to DAI if DAI had no governanace and was backed by WETH and WBTC
 *
 * It handles all the logic for minting and burning the tokens automatically
 * to make it pegged to USD at $1.00
 *
 * Our DSC smart contract should always be overcollatorlized at
 *    no point should the should our collatrol be equal below the value of all DSC
 */
import {DeccentralisedStablecoin} from "./Stablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/interfaces/feeds/AggregatorV3Interface.sol";

contract DSCEngine is ReentrancyGuard {
    // Errors-----------------------------------
    error DSCEngine_ValueMustBeGreaterThanZero();
    error DSCEngine_AddressMustNotBeZero();
    error DSCEngine_LengthOfTokenAndPriceFeedShouldBeSame();
    error DSCEngine_TransferOfTokenFailed();
    error DSCEngine_UserIsHealthFactorIsBroken(uint256 healthFactor);
    error DSCEngine_MintFailed();


    // State Variables-----------------------------------
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200 % overcollaterlised
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_userCollateralDeposited;
    mapping(address user => uint256 amountUserMintedDSC) private s_userDSCMinted;
    DeccentralisedStablecoin private immutable i_stableCoin;
    address[] private s_collatarelTokensAddress;

    // Events-----------------------------------
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    // Modifiers-----------------------------------
    modifier moreThanZero(uint256 value) {
        if (value <= 0) {
            revert DSCEngine_ValueMustBeGreaterThanZero();
        }
        _;
    }

    modifier notZeroAddress(address add) {
        if (add == address(0)) {
            revert DSCEngine_AddressMustNotBeZero();
        }
        _;
    }

    modifier allowedTokens(address token) {
        if (token == address(0)) {
            revert DSCEngine_AddressMustNotBeZero();
        }
        require(token == s_collatarelTokensAddress[0] || token == s_collatarelTokensAddress[1], "Token not allowed");
        _;
    }

    // Constructor-----------------------------------

    // WBTC 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43 PRICE IN USD
    // WETH 0x694AA1769357215DE4FAC081bf1f309aDC325306 PRICE IN USD
    constructor(address[] memory tokens, address[] memory priceFeeds, address dscStableCoinAddress) {
        if (tokens.length != priceFeeds.length) {
            revert DSCEngine_LengthOfTokenAndPriceFeedShouldBeSame();
        }
        for (uint256 i = 0; i < tokens.length; i++) {
            s_priceFeeds[tokens[i]] = priceFeeds[i];
            s_collatarelTokensAddress.push(tokens[i]);
        }
        i_stableCoin = DeccentralisedStablecoin(dscStableCoinAddress);
    }

    // External Functions-----------------------------------


    function depositCollateralAndMint() external{}

    /***
     * @param tokenColateralAdd address of the token that we want to deposit as collatrel
     * @param amountCollateral amount of the token that we want to deposit as collatrel
    */
    function depositCollateral(address tokenCollateralAdd, uint256 amountCollateral)
        external moreThanZero(amountCollateral) allowedTokens(tokenCollateralAdd) nonReentrant
    {
        s_userCollateralDeposited[msg.sender][tokenCollateralAdd] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAdd, amountCollateral);
        // As tokenCollateralAdd is ERC20 token so we need to transfer the token from user to this smart contract
        bool success = IERC20(tokenCollateralAdd).transferFrom(msg.sender, address(this), amountCollateral);
        if(!success) {
            revert DSCEngine_TransferOfTokenFailed();
        }
    }

    /**
     * Once the user has deposited the collateral, they can mint DSC with this function
     * 
     * Steps:Check the collatarel value is greater than the value of DSC, price Feeds

     * @param amountToMint amount of DSC to mint
     * @notice they should have more collatarel than the value of DSC to be minted
     */
    function mintDSC(uint256 amountToMint) external moreThanZero(amountToMint) nonReentrant {
        // We need to check if the user has enough collatarel to mint the DSC
        // example: if user wants $100 DSC to be minted but they have only $50 collatarel, the transaction should fail
        s_userDSCMinted[msg.sender] += amountToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_stableCoin.mint(msg.sender, amountToMint);
        if(!minted) {
            revert DSCEngine_MintFailed();
        }
    }

    function redeemCollateralDSC() external {}

    function checksUSDPrice() internal {}

    function burnDSC() external {}

    // This function will help us when price of Ethereum fluctuatates than the price can become low or high
    // If it is high than it is good because the smart contract is still overcollaterlised but when it drops
    // than it should have functionality to liquidate assests to make it overcollaterlised again
    function liquidate() external {}

    function getHealthFactor() external view {}


    // Private & Internal view Functions -----------------------------------

    function _getValueInUSD(address tokenAdd,uint256 amount) private view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenAdd]);
        (,int price,,,) = priceFeed.latestRoundData();
        /** 
         * We'll get price in 8 decimals so we need to convert it to 18 decimals
         * So price is in 8 decimals so we need to multiply it by 10^10 to get it in 18 decimals
         * After that price is converted then we can multiply it by the amount of token to get the value in USD
         * But it is still 18 decimals so we need to divde it by 10^18 to get value in usd
        */ 
        return ((uint256(price)*ADDITIONAL_FEED_PRECISION)*amount)/PRECISION;
    }

    function _getUserCollatarelAndDSCinUSD(address user) private view returns (uint256, uint256) {
        //below in userDSCMintedUSD the value is Already in USD as our token is pegged to USD but is 18 decimals
        uint256 userDSCMintedUSD = s_userDSCMinted[user]; 
        uint256 userCollaterelValueInUSD = getAccountCollateralValueInUSD(user); //there value is in USD
        return (userCollaterelValueInUSD, userDSCMintedUSD);
    }
    
    /**
     * @notice This function will check how close to liquidation
     * a user is based on the collatarel they have and the DSC they have minted.
     * 
     * If user goes below a certain health factor, we will liquidate their collatarel
     * to make sure the system is overcollaterlised
     */
    function _healthFactor(address user) private view returns(uint256){
        // We need
        // 1. Gathers total amount of collatarel in USD both in DSC and in collatarel staked in the protocol
        // 2. Total DSC minted by the user
        (uint256 totalCollatarelValueInUSD, uint256 totalDSCMintedInUSD) = _getUserCollatarelAndDSCinUSD(user);
        return _calculateHealthFactor(totalCollatarelValueInUSD, totalDSCMintedInUSD);
    }

    /**
     * This function is needed because in solidity we can't do decimals number
     * otherwise we could have done it like directly doing totalCollatarelValueInUSD/totalDSCMintedInUSD 
     * the value of that should be greater than 1.5 to be overcollaterlised
     * But we can't do that so we are coverting it in this way
     */
    function _calculateHealthFactor(uint256 collatarelValue,uint256 dscValue) internal pure returns(uint256){
        // $150 Eth /100 dsc = 1.5
        // $150 * 50 = 7500 => 7500/100 = 75/100 <1 so this user will be liquidated

        // $500 Eth/100 dsc = 5
        // $500 * 50 = 25000 => 25000/100 = 250/100 >1 so this user is overcollaterlised
        uint256 collateralAfterAdjustingTheThreshold = (collatarelValue * LIQUIDATION_THRESHOLD)/100;
        return (collateralAfterAdjustingTheThreshold * PRECISION)/dscValue;
    }

    // Check if they have enough collatarel
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor <= MIN_HEALTH_FACTOR) {
            revert DSCEngine_UserIsHealthFactorIsBroken(userHealthFactor);
        }
    }

    // Public, External, Pure and View Functions -----------------------------------


    function getAccountCollateralValueInUSD(address user) public view returns(uint256) {
        uint256 totalCollateralValue = 0;
        for (uint256 i = 0; i < s_collatarelTokensAddress.length; i++) {
            address token  = s_collatarelTokensAddress[i];
            uint256 collatarelAmount = s_userCollateralDeposited[user][token];

            totalCollateralValue += _getValueInUSD(token,collatarelAmount);
        }
        return totalCollateralValue;
    }
    

}
