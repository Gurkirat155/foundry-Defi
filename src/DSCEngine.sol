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

contract DSCEngine is ReentrancyGuard {
    // Errors-----------------------------------
    error DSCEngine_ValueMustBeGreaterThanZero();
    error DSCEngine_AddressMustNotBeZero();
    error DSCEngine_LengthOfTokenAndPriceFeedShouldBeSame();
    error DSCEngine_TransferOfTokenFailed();

    // State Variables-----------------------------------

    // address public WETH;
    // address public WBTC;
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
        require(token == address(WETH) || token == address(WBTC), "Token not allowed");
        _;
    }

    // Constructor-----------------------------------

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

    /**
     * @param tokenColateralAdd address of the token that we want to deposit as collatrel
     * @param amountCollateral amount of the token that we want to deposit as collatrel
     */
    function depositCollateral(address tokenCollateralAdd, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        allowedTokens(tokenCollateralAdd)
        nonReentrant
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
        revertIfHealthFactorIsBroken(msg.sender);
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

    function _getUserCollatarelAndDSC(address user) private view returns (uint256, uint256) {
        uint256 userDSCMinted = s_userDSCMinted[msg.sender];
        uint256 userCollaterelValue = s_userCollateralDeposited[user][address(WETH)] + s_userCollateralDeposited[user][address(WBTC)];
        return (userCollaterelValue, userDSCMinted);
    }
    
    /**
     * @notice This function will check how close to liquidation
     * a user is based on the collatarel they have and the DSC they have minted.
     * 
     * If user goes below a certain health factor, we will liquidate their collatarel
     * 
     * 
     */
    function _healthFactor(address user) private view{
        // We need
        // 1. Total collatarel value of the user
        // 2. Total DSC minted by the user

        (uint256 totalCollatarelValue, uint256 totalDSCMinted) = _getUserCollatarelAndDSC(user);
    }

    // Check if they have enough collatarel
    function _revertIfHealthFactorIsBroken(address user) private view {
        // Check the health factor of the user(do they have enough collatrell to mint the DSC)
        // Revert if not 
    }
    

}
