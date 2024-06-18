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
    error DSCEngine_NotEnoughCollatarelDeposited();
    error DSCEngine_NotEnoughDSCMinted();
    error DSCEngine_UserIsHealthFactorIsNotBroken(uint256 healthFactor);
    error DSCEngine__HealthFactorNotImproved();

    // State Variables-----------------------------------
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200 % overcollaterlised
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    uint256 private constant LIQUIDATION_BONUS = 10; //10% bonus to liquidator

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_userCollateralDeposited;
    mapping(address user => uint256 amountUserMintedDSC) private s_userDSCMinted;
    DeccentralisedStablecoin private immutable i_stableCoin;
    address[] private s_collatarelTokensAddress;

    // Events-----------------------------------
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollatarelRedeemed(address indexed from, address indexed to,address indexed token, uint256 amount);

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

    /***
     *
     * This function will deposit the collatarel and mint dsc in one transaction
     * @param tokenCollateralAdd
     * @param amountCollateral
     * @param amountToMint
     */
    function depositCollateralAndMint(address tokenCollateralAdd, uint256 amountCollateral, uint256 amountToMint)
        external
    {
        depositCollateral(tokenCollateralAdd, amountCollateral);
        mintDSC(amountToMint); //this is in usd
    }

    /***
     * @param tokenCollatarelAddress address of the token that we want to redeem
     * @param amountToRedeem amount of the token that we want to redeem
     * @param amountToBurn amount of DSC that we want to burn
     */
    function redeemCollatarelAndBurn(address tokenCollatarelAddress, uint256 amountToRedeem,uint256 amountToBurn) external {
        redeemCollateralDSC(tokenCollatarelAddress, amountToRedeem);
        burnDSC(amountToBurn);
    }

    // /**
    //  *
    //  * @param tokenColateralAdd address of the token that we want to deposit as collatrel
    //  * @param amountCollateral amount of the token that we want to deposit as collatrel
    //  */
    function depositCollateral(address tokenCollateralAdd, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        allowedTokens(tokenCollateralAdd)
        nonReentrant
    {
        s_userCollateralDeposited[msg.sender][tokenCollateralAdd] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAdd, amountCollateral);
        // As tokenCollateralAdd is ERC20 token so we need to transfer the token from user to this smart contract
        bool success = IERC20(tokenCollateralAdd).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine_TransferOfTokenFailed();
        }
    }

    /**
     * Once the user has deposited the collateral, they can mint DSC with this function
     *
     * Steps:Check the collatarel value is greater than the value of DSC, price Feeds
     *
     * @param amountToMint amount of DSC to mint
     * @notice they should have more collatarel than the value of DSC to be minted
     */
    function mintDSC(uint256 amountToMint) public moreThanZero(amountToMint) nonReentrant {
        // We need to check if the user has enough collatarel to mint the DSC
        // example: if user wants $100 DSC to be minted but they have only $50 collatarel, the transaction should fail
        (uint256 userCollaterelValueInUSD,)= _getUserCollatarelAndDSCinUSD(msg.sender);  
        if (amountToMint + s_userDSCMinted[msg.sender] >= userCollaterelValueInUSD/10e18 ){
            revert DSCEngine_NotEnoughCollatarelDeposited();
        }
        s_userDSCMinted[msg.sender] += amountToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_stableCoin.mint(msg.sender, amountToMint);
        if (!minted) {
            revert DSCEngine_MintFailed();
        }
    }

    // to redeem  the collatarel the user has submitted
    // TO redeem first we have to check the health factor of the user
    function redeemCollateralDSC(address tokenCollatarelAddress, uint256 amountToRedeem)
        public moreThanZero(amountToRedeem) nonReentrant(){
        
        _redeemCollatarel(msg.sender, msg.sender, tokenCollatarelAddress, amountToRedeem);

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function checksUSDPrice() internal {}

    function burnDSC(uint256 amount) moreThanZero(amount) public {
        if(amount >= s_userDSCMinted[msg.sender]){
            revert DSCEngine_NotEnoughDSCMinted();
        }
        _burnDSC(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**  
     * This function will help us when price of Ethereum fluctuatates, the price of Eth can become low or high
     * If it is high than it is good because the smart contract is still overcollaterlised but when it drops
     * than it should have functionality to liquidate assests to make it overcollaterlised again
     * Bonus will payed to someone to liquidate the user who is undercollaterlised
     * We can partially liquidate the user and check again if the user is still undercollaterlised
     * By getting their health factor
     * 
     * Only way to get bonus is if we assume that the protocol is overcollatralised minimum 200%
     * 
     * CEI --Checks , effects and Interactions
    */
    function liquidate(address tokenAddress, address user, uint256 debtToRecover) external moreThanZero(debtToRecover) nonReentrant() {
        uint256 startingHealthFactor = _healthFactor(user);
        if(startingHealthFactor>=MIN_HEALTH_FACTOR){
            revert DSCEngine_UserIsHealthFactorIsNotBroken(_healthFactor(user));
        }

        // We want to burn the DSC and redeem the collatarel
        // redeemCollatarelAndBurn(tokenAddress, debtToRecover);
        // First we pay the debt of the user in DSC and in terms of collatarel that has been provided
        // Then left over collatarel will be sent to the user
        // So we caluclate the value of the debt than convert the value in eth or btc 
        // And deduct it from collatarel and return to user
        // $100 DSC is the debt of the user
        // First we caluclate $100 the value of the debt in Eth or Btc
        // then we deduct it from the collatarel that user has submitted
        // Return the remaining to the user

        uint256 userCollatarelToRecover = getTokenAmountFromUSD(tokenAddress,debtToRecover); //This is DSC tokens so we got the Debt in usd
        // uint256 userDebtValueInETHorBTC = _getValueInUSD(tokenAddress, userDebtToRecover); //Got the value debt in ETH 
        // Now we have to incentevise the msg.sender who is doin this

        // So if debt to recover is 
        // 0.05 ETH so 10% will be bonus paid to the liquidator
        uint256 bonusCollatarel = (userCollatarelToRecover * LIQUIDATION_BONUS)/100;

        // First we will redeem the collatreal of the user
        // The burn the dsc of the user
        // redeemCollateralDSC(tokenAddress, userCollatarelToRecover);
        // burnDSC(debtToRecover);

        _redeemCollatarel(user, msg.sender, tokenAddress, userCollatarelToRecover + bonusCollatarel);
        _burnDSC(debtToRecover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        // This conditional should never hit, but just in case
        if (endingUserHealthFactor <= startingHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }


    function getHealthFactor() external view {}

    // Private & Internal view Functions -----------------------------------

    function _getValueInUSD(address tokenAdd, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenAdd]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        /**
         * We'll get price in 8 decimals so we need to convert it to 18 decimals
         * So price is in 8 decimals so we need to multiply it by 10^10 to get it in 18 decimals
         * After that price is converted then we can multiply it by the amount of token to get the value in USD
         * But it is still 18 decimals so we need to divde it by 10^18 to get value in usd
         */
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
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
    function _healthFactor(address user) private view returns (uint256) {
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
    function _calculateHealthFactor(uint256 collatarelValue, uint256 dscValue) internal pure returns (uint256) {
        // $150 Eth /100 dsc = 1.5
        // $150 * 50 = 7500 => 7500/100 = 75/100 <1 so this user will be liquidated

        // $500 Eth/100 dsc = 5
        // $500 * 50 = 25000 => 25000/100 = 250/100 >1 so this user is overcollaterlised
        uint256 collateralAfterAdjustingTheThreshold = (collatarelValue * LIQUIDATION_THRESHOLD) / 100;
        return (collateralAfterAdjustingTheThreshold * PRECISION) / dscValue;
    }

    // Check if they have enough collatarel
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor <= MIN_HEALTH_FACTOR) {
            revert DSCEngine_UserIsHealthFactorIsBroken(userHealthFactor);
        }
    }

    function _redeemCollatarel(address from,address to, address tokenCollatarelAddress,uint256 amountToRedeem) private {

        if(amountToRedeem >= s_userCollateralDeposited[from][tokenCollatarelAddress]){
            revert DSCEngine_NotEnoughCollatarelDeposited();
        }
        
        s_userCollateralDeposited[from][tokenCollatarelAddress] -= amountToRedeem;
        emit CollatarelRedeemed(from, to ,tokenCollatarelAddress, amountToRedeem);
        bool success = IERC20(tokenCollatarelAddress).transfer(to, amountToRedeem);
        if(!success){
            revert DSCEngine_TransferOfTokenFailed();
        }

    }

    function _burnDSC(uint256 amountToBurn,address onBehalfOf, address dscFrom) private {
        if(amountToBurn >= s_userDSCMinted[onBehalfOf]){
            revert DSCEngine_NotEnoughDSCMinted();
        }
        // Bug there is problem the user might have
        // The i_stablecoin in the address in the smart contract of token 
        // Because what we are doing in _redeemCollatarel and _burnDSCcombined is 
        // First transfering the weth to liquidator than but the dsc minted or dsc balance of the 
        // Liqudator is zero than in burndsc we are transfering the amount to this address in dsc from 
        // Liqudator in dsc which he doesn't have he has weth pr wbtc in his currency that he can recover from

        s_userDSCMinted[onBehalfOf] -= amountToBurn;
        bool success = i_stableCoin.transferFrom(dscFrom,address(this), amountToBurn);
        if(!success){
            revert DSCEngine_TransferOfTokenFailed();
        }
        i_stableCoin.burn(amountToBurn);
    }

    // Public, External, Pure and View Functions -----------------------------------

    function getAccountCollateralValueInUSD(address user) public view returns (uint256) {
        uint256 totalCollateralValue = 0;
        for (uint256 i = 0; i < s_collatarelTokensAddress.length; i++) {
            address token = s_collatarelTokensAddress[i];
            uint256 collatarelAmount = s_userCollateralDeposited[user][token];

            totalCollateralValue += _getValueInUSD(token, collatarelAmount);
        }
        return totalCollateralValue;
    }

    function getTokenAmountFromUSD(address tokenAdd, uint256 amountInUSDInWei) public view returns (uint256) {
        // Price of ETh or btc token in USD
        // (usd/eth)*amountInUSD =  will give price in Eth of the amount 
        // but we have eth/usd we will divide amountInUSD/(eth/usd) = we will get the price
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenAdd]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // ($10e18 * 1e18) / 2000e8 * 1e10 = 5e15 
        // 5000000000000000
        return ((amountInUSDInWei * PRECISION) /uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountInfo(address user) external view returns(uint256,uint256){
        return _getUserCollatarelAndDSCinUSD(user);
    }

    function getValueInUSD(address tokenAdd, uint256 amount) public view returns(uint256){
        return _getValueInUSD(tokenAdd, amount);
    }

    



    
}
