// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeccentralisedStablecoin} from "../../src/Stablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../Mocks/MockERC20.sol";

contract TestingDSCEngine is Test {
    DSCEngine dsc_Engine;
    DeccentralisedStablecoin stable_coin;
    DeployDSC deployDSC;
    HelperConfig helper_Config;

    address wethUSDPriceFeed;
    address wbtcUSDPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;


    address addr1 = makeAddr("user1");
    address addr2 = makeAddr("user2");
    uint256 public constant userCollatarel = 10 ether;
    uint256 public constant userBalance = 20 ether;
    uint256 public constant PRECSION = 1e18;

    function setUp() public {
        deployDSC = new DeployDSC();
        (stable_coin, dsc_Engine, helper_Config) = deployDSC.run();

        (wethUSDPriceFeed, wbtcUSDPriceFeed, weth, wbtc, deployerKey) = helper_Config.activeConfig();
        if (block.chainid == 31337) {
             vm.deal(addr1, userBalance);
        }
       
        ERC20Mock(weth).mint(addr1, userCollatarel);
        ERC20Mock(wbtc).mint(addr1, userCollatarel);
        vm.deal(addr2, 10 ether);
    }

    modifier depositCollatarel(address user){
        vm.deal(user, userBalance);
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsc_Engine), userCollatarel);
        dsc_Engine.depositCollateral(weth, userCollatarel);
        vm.stopPrank();
        _;
    }

    modifier depositCollatarelAndMintDSC(address user){
        vm.deal(user, userBalance);
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsc_Engine), userCollatarel);
        dsc_Engine.depositCollateralAndMint(weth, userCollatarel, 2000);
        _;
    }

    function checkMsgsender(address msgSender, address comparedAddress) public pure returns (bool) {
        return msgSender == comparedAddress;
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////

    address[] public priceFeeds;
    address[] public tokenAddress;

    function testRevertIfTokenLengthDoesntMatchPublicFeed() public {
        priceFeeds.push(wethUSDPriceFeed);
        priceFeeds.push(wbtcUSDPriceFeed);
        tokenAddress.push(weth);
        

        vm.expectRevert(DSCEngine.DSCEngine_LengthOfTokenAndPriceFeedShouldBeSame.selector);
        new DSCEngine(priceFeeds, tokenAddress, address(stable_coin));

    }

    ///////////////////////
    // Price Tests ////////
    ///////////////////////


    function testTokenPriceInFromUSDToEth() public  view{
        // 1 eth = 3400 usd
        // 1000usd = 1000/3400 eth = 0.2941176470588235 eth
        uint256 amountInUSDInWei = 1000e18;
        uint256 expectedPrice = 29411764705882352941176470580000000000;
        // 29411764705882352941176470580000000000
        uint256 value = dsc_Engine.getTokenAmountFromUSD(weth, amountInUSDInWei);
        console.log("Value: ", value);
        assertEq(value, expectedPrice, "Price should be 0.2941176470588235 eth");
    }


    ///////////////////////
    // Ownership Tests ////////
    ///////////////////////

    function testOwnerOfStableCoin() public view {
        address owner = stable_coin.owner();
        assertEq(owner, address(dsc_Engine), "Owner should be DSCEngine");
    }

    function testCheckOwnerBal() public returns (uint256) {
        vm.startPrank(address(dsc_Engine));
        uint256 bal = stable_coin.balanceOf(address(dsc_Engine));
        uint256 totalSupply = stable_coin.totalSupply();
        console.log("Balance of DSCEngine: ", bal);
        console.log("Total Supply of DSC: ", totalSupply);
        assertEq(bal, totalSupply);
        return bal;
    }

    ///////////////////////
    // Deposit Tests ////////
    ///////////////////////

    function testRevertIfCollateralIsZero() public {
        vm.prank(addr1);
        ERC20Mock(weth).approve(address(dsc_Engine), 10 ether);

        vm.expectRevert(DSCEngine.DSCEngine_ValueMustBeGreaterThanZero.selector);
        dsc_Engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertNonTokenAddress() public {
        ERC20Mock randomToken = new ERC20Mock("Hi", "HELLO", addr1, 1000e8);
        vm.prank(addr1);
        randomToken.approve(address(dsc_Engine), 8 ether);
        vm.expectRevert("Token not allowed");
        dsc_Engine.depositCollateral(address(randomToken), 8 ether);
        vm.expectRevert(DSCEngine.DSCEngine_AddressMustNotBeZero.selector);
        dsc_Engine.depositCollateral(address(0), 8 ether);
        vm.stopPrank();
    }

    function testDepositCollatarelAndGetAccountinfo()  public depositCollatarel(addr1)  {
        (uint256 collateral, uint256 debt) = dsc_Engine.getAccountInfo(addr1);
        console.log("Collateral USD: ", collateral); //34000000000000000000000
        console.log("Debt: ", debt);
        uint256 collatarelValueInEth = dsc_Engine.getTokenAmountFromUSD(weth, collateral);
        console.log("Collateral ETH: ", collatarelValueInEth/PRECSION); //1000000000000000000000000000000000000000 10e38
        console.log("Amount Collateral ETH: ", userCollatarel); //10000000000000000000 PRECSION
        assertEq(collatarelValueInEth/10e19, userCollatarel);
        assertEq(debt, 0);
    }

    ///////////////////////
    // Minting Tests ////////
    ///////////////////////

    function testMintDSCRevertsIfAmountIsZero() public depositCollatarel(addr1) {
        vm.startPrank(addr1);
        vm.expectRevert(DSCEngine.DSCEngine_ValueMustBeGreaterThanZero.selector);
        dsc_Engine.mintDSC(0);
        vm.stopPrank();
    }

    function testMintDSC() public depositCollatarel(addr1) {
        vm.startPrank(addr1);
        console.log(stable_coin.balanceOf(addr1));
        dsc_Engine.mintDSC(10); //minting in usd price not in eth
        (,uint256 balance) = getCollatarelInUSD(addr1);
        console.log(balance);
        assertEq(balance, 10, "Minted DSC should be 1 ether");
        vm.stopPrank();
    }

    function testMintDSCRevertsIfNotEnoughCollateral() public depositCollatarel(addr1) {
        // Address 1 balance is $3400
        uint256 collatarelSubmitted = 34000;
        uint256 mintAmount = 3600; // In USD
        (uint256 collatarel, uint256 debt) = getCollatarelInUSD(addr1);

        vm.startPrank(addr1);
        vm.expectRevert(DSCEngine.DSCEngine_NotEnoughCollatarelDeposited.selector);
        // console.log("Collatarel In USD Submitted: ", collatarel);
        assertEq(collatarel, collatarelSubmitted);
        dsc_Engine.mintDSC(mintAmount); // Debt in usd
        (,debt) = getCollatarelInUSD(addr1);
        // console.log("Debt After Minting: ", debt);
        assertEq(debt,0);
        vm.stopPrank();
    }

    function testMintingThriceToCheckIfDebtGetsAdded() public depositCollatarel(addr1){
        // Address 1 collatarel is $3400
        uint256 mintAmount1 = 300; // In USD
        uint256 mintAmount2 = 400; // In USD
        uint256 mintAmount3 = 2150; // In USD
        (,uint256 debt) = getCollatarelInUSD(addr1);

        vm.startPrank(addr1);
        // console.log("Collatarel In USD Submitted: ", collatarel);

        dsc_Engine.mintDSC(mintAmount1); // Debt in usd
        (,debt) = getCollatarelInUSD(addr1);
        console.log("Debt After Minting Once: ", debt);
        assertEq(debt,mintAmount1);

        dsc_Engine.mintDSC(mintAmount2); // Debt in usd
        (,debt) = getCollatarelInUSD(addr1);
        console.log("Debt After Minting Twice: ", debt);
        assertEq(debt,mintAmount1 + mintAmount2);

        dsc_Engine.mintDSC(mintAmount3); // Debt in usd
        (,debt) = getCollatarelInUSD(addr1);
        console.log("Debt After Minting Thrice: ", debt);
        assertEq(debt,mintAmount1 + mintAmount2 + mintAmount3);

        // dsc_Engine.mintDSC(2150); // Debt in usd
        // (,debt) = getCollatarelInUSD(addr1);
        // console.log("Debt After Minting Thrice: ", debt);
        // assertEq(debt,3350);

        vm.stopPrank();
    }

    // write test case to  Check if health factor reverts or not 
    // Write a test case for minting before depositing 


    ///////////////////////////////////////////
    // Deposit and Mint function Tests ////////
    ///////////////////////////////////////////

    function testDepositCollateralAndMint() public {
        // address tokenCollateralAdd, uint256 amountCollateral, uint256 amountToMint

        // Arrange
        uint256 collatarelToDeposit = userCollatarel;
        uint256 debtToTake = 600; //In USD
        vm.deal(addr1, userCollatarel);
        vm.startPrank(addr1);
        ERC20Mock(weth).approve(address(dsc_Engine),userCollatarel);

        // Act
        dsc_Engine.depositCollateralAndMint(weth, collatarelToDeposit, debtToTake);
        (uint256 collatarel, uint256 debt) = getCollatarelInUSD(addr1);
        vm.stopPrank();

        // Assert
        assertEq(collatarel, 34000);
        assertEq(debt, debtToTake);
    }


    ///////////////////////
    // Redeem Tests ////////
    ///////////////////////

    function testRedeemCollateralRevertsIfAmountIsZero() public depositCollatarel(addr1) {
        vm.startPrank(addr1);
        vm.expectRevert(DSCEngine.DSCEngine_ValueMustBeGreaterThanZero.selector);
        dsc_Engine.redeemCollateralDSC(weth, 0);
    }

    function testRedeemCollateralRevertsIfNotEnoughCollateral() public depositCollatarelAndMintDSC(addr1) {
        vm.startPrank(addr1);
        vm.expectRevert(DSCEngine.DSCEngine_NotEnoughCollatarelDeposited.selector);
        dsc_Engine.redeemCollateralDSC(weth, 100 ether); // Exceeds deposited amount
    }

    function testRedeemCollateral() public depositCollatarelAndMintDSC(addr1) {
        vm.startPrank(addr1);

        // Arrange
        (uint256 startCollateral,) = dsc_Engine.getAccountInfo(addr1);
        uint256 amountToRedeem = 6 ether; // amount in ether
        console.log("Amount to redeem: ",amountToRedeem);
        console.log("Start Collatarel: ",startCollateral);
        
        // Act
        dsc_Engine.redeemCollateralDSC(weth,amountToRedeem);
        (uint256 finalCollateral, ) = dsc_Engine.getAccountInfo(addr1);
        uint256 getValueOfRedeemInUSD = dsc_Engine.getValueInUSD(weth, amountToRedeem);

        console.log("Final Collatarel: ",finalCollateral);
        console.log("Remaining Collatarel: ",startCollateral - getValueOfRedeemInUSD);
        console.log("Redeem Value In USD: ",getValueOfRedeemInUSD);

        // Assert
        assertEq(finalCollateral, startCollateral-getValueOfRedeemInUSD);
    }


    ///////////////////////
    // Burn Tests ////////
    ///////////////////////

    function testBurnDSCRevertsIfAmountIsZero() public depositCollatarelAndMintDSC(addr1) {
        vm.startPrank(addr1);
        vm.expectRevert(DSCEngine.DSCEngine_ValueMustBeGreaterThanZero.selector);
        dsc_Engine.burnDSC(0);
    }

    function testRevertBurnMoreDScThanMinted() public {}


     function testBurnDSC() public depositCollatarelAndMintDSC(addr1) {
        vm.startPrank(addr1);

        // Arrange
        uint256 amountToBurnInDSC = 500; // usd
        (uint256 collateral, uint256 debt) = dsc_Engine.getAccountInfo(addr1);
        console.log("Collatarel: ", collateral);
        console.log("Debt: ", debt);

        // Act
        stable_coin.approve(address(dsc_Engine),amountToBurnInDSC);
        dsc_Engine.burnDSC(amountToBurnInDSC);
        uint256 balance = stable_coin.balanceOf(addr1);
        console.log("Debt After Burn: ",balance);

        // how can a user burn without even redeeming first
        
        // Assert
        assertEq(balance, debt - amountToBurnInDSC, "Burned DSC should be 0");
    }

    // Check health factor
    // Check for burning before redeeming
    // Test if amount redeem is less which means not enough collatarel, so careful that user doesn't  dsc 
    // Buring more dsc than the user has minted
    // redeem and burn function testing remaining

    ///////////////////////
    // Liquidation Tests ////////
    ///////////////////////

    function testLiquidateRevertsIfAmountIsZero() public depositCollatarelAndMintDSC(addr1) {
        vm.startPrank(addr1);
        vm.expectRevert(DSCEngine.DSCEngine_ValueMustBeGreaterThanZero.selector);
        dsc_Engine.liquidate(weth, addr1,0);
    }

    // function testLiquidate() public depositCollatarelAndMintDSC(addr1) {

        
    //     uint256 amountToRedeem = 9.8 ether; // amount in ether


    //     vm.startPrank(addr1);
    //     dsc_Engine.redeemCollateralDSC(weth,amountToRedeem);

    //     vm.startPrank(addr2);
    //     dsc_Engine.liquidate(weth,addr1, 100);

    //     // uint256 balance = dsc_Engine.getAccountCollateralValueInUSD(addr1);
    //     // uint256 expectedBalance = dsc_Engine.getTokenAmountFromUSD(weth, userCollatarel - 1 ether);
    //     // assertEq(balance, expectedBalance, "Liquidated collateral value should match");
    // }


    // Health factor and Liquadations test remaining

    
    ///////////////////////
    // Getter Functions ////////
    ///////////////////////

    function getCollatarelInUSD(address user)public view returns(uint256,uint256){
        (uint256 collateral, uint256 debt) = dsc_Engine.getAccountInfo(user);
        // console.log("Collatarel USD: ",collateral/PRECSION);
        uint256 collatarelUSD = collateral/PRECSION;
        return (collatarelUSD,debt);
    }

    
    
}


// function testMintingFunction() public {
    //     // console.log(weth);
    //     dsc_Engine.depositCollateral(weth, 1000);
    //     dsc_Engine.mintDSC(1000);
    //     stable_coin.mint(address(dsc_Engine),1000);
    //     console.log(stable_coin.totalSupply());
    //     assertEq(testCheckOwnerBal(), 1000);
    // }

    // function testDepositCollateral() public {
    //     dsc_Engine.depositCollateral(weth, 1000);
    //     console.log()
    // }