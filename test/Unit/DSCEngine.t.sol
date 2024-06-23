// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeccentralisedStablecoin} from "../../src/Stablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../Mocks/MockERC20.sol";
import {MockV3Aggregator} from "../Mocks/MockAggregator.sol";

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
    uint256 private constant LIQUIDATION_BONUS = 10;

    function setUp() public {
        deployDSC = new DeployDSC();
        (stable_coin, dsc_Engine, helper_Config) = deployDSC.run();

        (wethUSDPriceFeed, wbtcUSDPriceFeed, weth, wbtc, deployerKey) = helper_Config.activeConfig();
        if (block.chainid == 31337) {
             vm.deal(addr1, userBalance);
             vm.deal(addr2, userBalance);
        }
       
        ERC20Mock(weth).mint(addr1, userCollatarel);
        ERC20Mock(wbtc).mint(addr1, userCollatarel);
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
        dsc_Engine.depositCollateralAndMint(weth, userCollatarel, 2000 ether);
        vm.stopPrank();
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
        uint256 expectedPrice = 294117647058823529;
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
        assertEq(collatarelValueInEth, userCollatarel);
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
        uint256 amountToMint = 10 ether; // In USD in wei
        vm.startPrank(addr1);
        console.log(stable_coin.balanceOf(addr1));
        dsc_Engine.mintDSC(amountToMint); //minting in usd price not in eth
        (,uint256 balance) = dsc_Engine.getAccountInfo(addr1);
        console.log(balance);
        assertEq(balance, amountToMint, "Minted DSC should be 1 ether");
        vm.stopPrank();
    }

    function testMintDSCRevertsIfNotEnoughCollateral() public depositCollatarel(addr1) {
        // Address 1 balance is $34000
        uint256 collatarelSubmitted = 34000;
        uint256 mintAmount = 18000 ether; // In USD but in 10e18 so 15000*10e18
        (uint256 collatarel, uint256 debt) = getCollatarelInUSD(addr1);

        vm.startPrank(addr1);
        vm.expectRevert();
        console.log("Collatarel In USD Submitted: ", collatarel);
        assertEq(collatarel, collatarelSubmitted);
        dsc_Engine.mintDSC(mintAmount); // Debt in usd
        (collatarel,debt) = getCollatarelInUSD(addr1);
        console.log("Debt After Minting: ", debt);
        console.log("Collatarel After Minting: ", collatarel);
        console.log(dsc_Engine.getAccountCollateralValueInUSD(addr1));
        assertEq(debt,0);
        vm.stopPrank();
    }

    function testMintingThriceToCheckIfDebtGetsAdded() public depositCollatarel(addr1){
        // Address 1 collatarel is $3400
        uint256 mintAmount1 = 300 ether; // In USD in wei
        uint256 mintAmount2 = 400 ether; // In USD in wei
        uint256 mintAmount3 = 2150 ether; // In USD in wei
        (,uint256 debt) = getCollatarelInUSD(addr1);

        vm.startPrank(addr1);
        // console.log("Collatarel In USD Submitted: ", collatarel);

        dsc_Engine.mintDSC(mintAmount1); // Debt in usd
        (,debt) = dsc_Engine.getAccountInfo(addr1);
        console.log("Debt After Minting Once: ", debt);
        assertEq(debt,mintAmount1);

        dsc_Engine.mintDSC(mintAmount2); // Debt in usd
        (,debt) = dsc_Engine.getAccountInfo(addr1);
        console.log("Debt After Minting Twice: ", debt);
        assertEq(debt,mintAmount1 + mintAmount2);

        dsc_Engine.mintDSC(mintAmount3); // Debt in usd
        (,debt) = dsc_Engine.getAccountInfo(addr1);
        console.log("Debt After Minting Thrice: ", debt);
        assertEq(debt,mintAmount1 + mintAmount2 + mintAmount3);

        // dsc_Engine.mintDSC(2150); // Debt in usd
        // (,debt) = dsc_Engine.getAccountInfo(addr1);
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
        uint256 debtToTake = 600 ether; //In USD in wei
        vm.deal(addr1, userCollatarel);
        vm.startPrank(addr1);
        ERC20Mock(weth).approve(address(dsc_Engine),userCollatarel);

        // Act
        dsc_Engine.depositCollateralAndMint(weth, collatarelToDeposit, debtToTake);
        (uint256 collatarel, uint256 debt) = getCollatarelInUSD(addr1);
        vm.stopPrank();

        // Assert
        assertEq(collatarel, 34000);
        assertEq(debt, debtToTake/PRECSION);
    }


    ///////////////////////
    // Redeem Tests ////////
    ///////////////////////

    function testRedeemCollateralRevertsIfAmountIsZero() public depositCollatarel(addr1) {
        vm.startPrank(addr1);
        vm.expectRevert(DSCEngine.DSCEngine_ValueMustBeGreaterThanZero.selector);
        dsc_Engine.redeemCollateralDSC(weth, 0);
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
    

    function testMustRedeemMoreThanZero() public depositCollatarelAndMintDSC(addr1) {
        vm.startPrank(addr1);
        stable_coin.approve(address(dsc_Engine), 200 ether);
        vm.expectRevert(DSCEngine.DSCEngine_ValueMustBeGreaterThanZero.selector);
        dsc_Engine.redeemCollatarelAndBurn(weth, 0, 200 ether);
        vm.stopPrank();
    }

    function testBurnMoreDSC() public depositCollatarelAndMintDSC(addr1) {
        vm.startPrank(addr1);
        stable_coin.approve(address(dsc_Engine), 2000 ether);
        vm.expectRevert(DSCEngine.DSCEngine_NotEnoughDSCMinted.selector);
        dsc_Engine.redeemCollatarelAndBurn(weth, 5 ether, 3000 ether);
        vm.stopPrank();

    }

    function testReddemAndBurnDSC() public depositCollatarelAndMintDSC(addr1){
        //Arrange
        uint256 amountToRedeem = 6 ether; // amount in ether 6 ETH 
        uint256 amountToRedeemInUSD = getValueInUSD(weth, amountToRedeem);
        uint256 amountToBurn = 500 ether; // amount in ether $500
        (uint256 collatarelBefore, uint256 debtBefore) = getCollatarelInUSD(addr1);
        console.log("Collatarel Before: ", collatarelBefore);
        console.log("Debt Before: ", debtBefore);
        assertEq(dsc_Engine.getCollateralDeposited(addr1,weth) , 10 ether);

        //Act
        vm.startPrank(addr1);
        stable_coin.approve(address(dsc_Engine), amountToBurn);
        dsc_Engine.redeemCollatarelAndBurn(weth,amountToRedeem, amountToBurn);
        (uint256 collatarelAfter, uint256 debtAfter) = getCollatarelInUSD(addr1);
        console.log("Collatarel After: ", collatarelAfter);
        console.log("Debt After: ", debtAfter);

        //Assert
        assertEq(collatarelAfter, collatarelBefore - amountToRedeemInUSD);
        assertEq(debtAfter, debtBefore - amountToBurn/1e18);
    }


    function testReddemMoreCollatarel() public  depositCollatarelAndMintDSC(addr1){
        // Arrange
        uint256 amountToRedeem = 9 ether; // amount in ether
        uint256 amountToBurn = 500 ether; // amount in ether
    

        // Act
        vm.startPrank(addr1);
        stable_coin.approve(address(dsc_Engine), amountToBurn);
        vm.expectRevert();
        dsc_Engine.redeemCollatarelAndBurn(weth,amountToRedeem, amountToBurn);
        vm.stopPrank();
    }

    ///////////////////////
    // Health Factor tests ////////
    ///////////////////////

    function testHealthFactor() public depositCollatarelAndMintDSC(addr1) {
        // Arrange

        // if calltarel submitted and minted than calucalte manually the health factor
        uint256 amountToDeposit = 10 ether; //In eth
        uint256 amountToMint = 2000; // in USD
        uint256 amountOfCollatarelInUSD = dsc_Engine.getValueInUSD(weth, amountToDeposit);// in USD but in WEI
        // amountOfCollatarelInUSD 34000,000000000000000000
        uint256 overcollatarilsedAmount = 50; //which is 200% of the collatarel
        (uint256 collatarel,) = getCollatarelInUSD(addr1);
        console.log("Collatarel In USD: ", amountOfCollatarelInUSD);
        console.log("Collatarel: ", collatarel);

        // from total $34000 of the collatarel submitted, only only 50% of 34000 can be minted
        // Means at max we can mint 17000
    
        uint256 amountThatCanBeMinted = (amountOfCollatarelInUSD * overcollatarilsedAmount)/100; // This is amximum amount that can be minted $17000
        // amountThatCanBeMinted 17000,000000000000000000 
        console.log("Amount That Can Be Minted: ", amountThatCanBeMinted/100);
        // 17000,0000000000000000
        uint256 healthFactorAfterMinting =  amountThatCanBeMinted/amountToMint;
        // 8,500000000000000000
        console.log("Health Factor After Minting: ", healthFactorAfterMinting);
        

        // Act
        vm.startPrank(addr1);
        uint256 healthFactor = dsc_Engine.getHealthFactor(addr1);
        console.log("Health Factor With Deposit: ", healthFactor);
        vm.stopPrank();

        // Assert
        assertEq(healthFactor, healthFactorAfterMinting);
    }


    function testHealthFactorAfterMultipleMinting() public depositCollatarel(addr1) {
        
        // Arrange
        uint256 amountOfCollatarelDeposited = 34000 ether; // in USD in wei
        uint256 amountToMint1 = 3000 ether; // in USD
        uint256 amountToMint2 = 4000 ether; // in USD
        uint256 amountToMint3 = 10000 ether; // in USD
        uint256 amountToMint4 = 20000 ether; // in USD

        assertEq(
            dsc_Engine.getHealthFactor(addr1),type(uint256).max,
            "Health factor should be max because nothing is minted yet"
        );

        // Act
        vm.startPrank(addr1);
        dsc_Engine.mintDSC(amountToMint1);
        uint256 healthFactorAfterMinting1 = dsc_Engine.getHealthFactor(addr1);
        console.log("Health Factor After Minting 1: ", healthFactorAfterMinting1/PRECSION);

        dsc_Engine.mintDSC(amountToMint2);
        uint256 healthFactorAfterMinting2 = dsc_Engine.getHealthFactor(addr1);
        console.log("Health Factor After Minting 2: ", healthFactorAfterMinting2/PRECSION);

        dsc_Engine.mintDSC(amountToMint3);
        uint256 healthFactorAfterMinting3 = dsc_Engine.getHealthFactor(addr1);
        console.log("Health Factor After Minting 3: ", healthFactorAfterMinting3/PRECSION);

        //Assert
        assertEq(healthFactorAfterMinting1 > healthFactorAfterMinting2, true);
        assertEq(healthFactorAfterMinting2 > healthFactorAfterMinting3, true);

        
        vm.expectRevert();
        dsc_Engine.mintDSC(amountToMint4);
        vm.stopPrank();

        (uint256 collatarel, uint256 debt) = dsc_Engine.getAccountInfo(addr1);
        // console.log("Collatarel: ", collatarel);
        // console.log("Debt: ", debt);
        assertEq(collatarel, amountOfCollatarelDeposited);
        assertEq(debt, amountToMint1 + amountToMint2 + amountToMint3);
        
    }


    ///////////////////////
    // Liquidation Tests ////////
    ///////////////////////

    function testLiquidateRevertsIfAmountIsZero() public depositCollatarelAndMintDSC(addr1) {
        vm.startPrank(addr1);
        vm.expectRevert(DSCEngine.DSCEngine_ValueMustBeGreaterThanZero.selector);
        dsc_Engine.liquidate(weth, addr1,0);
    }

    // function testLiquidate() public depositCollatarelAndMintDSC(addr1) {

    //     uint256 amountOfLiquidation = dsc_Engine.getTokenAmountFromUSD(weth, 3400 ether);
    //     console.log(3400 ether);
    //     // 3400 000000000000000000
    //     // console.log("Amount of Liquidation Before Price Change: ", amountOfLiquidation);
    //     console.log("Health Factor Before: ", dsc_Engine.getHealthFactor(addr1));
    //     assertEq(amountOfLiquidation, 1 ether);
    //     (uint256 collatarel, uint256 debt) = getCollatarelInUSD(addr1);
    //     console.log("Collatarel Before: ", collatarel);
    //     console.log("Debt Before: ", debt);

    //     int256 ethUsdPriceUpdate = 100e8; // 1 ETH = $1000
    //     MockV3Aggregator(wethUSDPriceFeed).updateAnswer(ethUsdPriceUpdate);
    //     console.log("Health Factor After: ", dsc_Engine.getHealthFactor(addr1));

    //     ( collatarel,  debt) = getCollatarelInUSD(addr1);
    //     console.log("Collatarel After: ", collatarel);
    //     console.log("Debt After: ", debt);

    //     uint256 balance = 50 ether;
    //     ERC20Mock(weth).mint(addr2, balance);

    //     vm.deal(addr2, balance);
    //     vm.startPrank(addr2);
    //     ERC20Mock(weth).approve(address(dsc_Engine), balance);
    //     // Minting 100 DSC Deposited 50 ETH ==50*1000 = $50000
    //     dsc_Engine.depositCollateralAndMint(weth, balance, 2000 ether);
    //     stable_coin.approve(address(dsc_Engine), 2000 ether);
    //     dsc_Engine.liquidate(weth, addr1, 2000 ether); // We are covering their whole debt
    //     // dsc_Engine._redeemCollatarel(addr1, addr2, weth, 10000 ether);
    //     vm.stopPrank();

    //     console.log("Health Factor After Liquidation: ", dsc_Engine.getHealthFactor(addr1));

    // // 8500000000000000000
    // // 250000000000000000
    // }


    // function testLiquidate() public depositCollatarelAndMintDSC(addr1)  {

    //     vm.prank(addr1);
    //     dsc_Engine.mintDSC(6000 ether);
    //     vm.stopPrank();

    //     uint256 amountToLiquidate = 8000 ether; // in Eth
    //     // uint256 amountToRedeemInETH = 8 ether; // amount in ether
    //     // uint256 amountToRedeemInUSD = dsc_Engine.getValueInUSD(weth, amountToRedeemInETH);
    //     // console.log("Amount to redeem in USD: ", amountToRedeemInUSD);
    //     (uint256 collatarel1Before, uint256 debt1Before) = getCollatarelInUSD(addr1);
    //     console.log("Collatarel 1: ", collatarel1Before);
    //     console.log("Debt 1: ", debt1Before);
        

    //     int256 ethUsdPriceUpdate = 100e8;
    //     MockV3Aggregator(wethUSDPriceFeed).updateAnswer(ethUsdPriceUpdate);


    //     (uint256 collatarel1After, uint256 debt1After) = getCollatarelInUSD(addr1);
    //     console.log("Collatarel 1 After: ", collatarel1After);
    //     console.log("Debt 2 After: ", debt1After);
    //     vm.startPrank(addr2);
    //     // dsc_Engine.depositCollateralAndMint(tokenCollateralAdd, amountCollateral, amountToMint);
    //     // ERC20Mock(weth).approve(address(dsc_Engine), 100 ether);
    //     // dsc_Engine.depositCollateralAndMint(weth, userBalance, 20 ether);
    //     // stable_coin.approve(address(dsc_Engine), 100 ether);
    //     ERC20Mock(weth).approve(address(dsc_Engine), userCollatarel);
    //     dsc_Engine.depositCollateral(weth, userCollatarel);
    //     dsc_Engine.liquidate(weth,addr1, 10 ether);

    //     // uint256 balance = dsc_Engine.getAccountCollateralValueInUSD(addr1);
    //     // uint256 expectedBalance = dsc_Engine.getTokenAmountFromUSD(weth, userCollatarel - 1 ether);
    //     // assertEq(balance, expectedBalance, "Liquidated collateral value should match");



    //     vm.startPrank(addr1);
    //     ERC20Mock(weth).approve(address(dsc_Engine), userCollatarel);
    //     dsc_Engine.depositCollateralAndMint(weth, userCollatarel, userBalance);
    //     vm.stopPrank();
    //     int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

    //     MockV3Aggregator(wethUSDPriceFeed).updateAnswer(ethUsdUpdatedPrice);
    //     uint256 userHealthFactor = dsc_Engine.getHealthFactor(addr1);

    //     ERC20Mock(weth).mint(addr2, 100 ether);

    //     vm.startPrank(addr2);
    //     ERC20Mock(weth).approve(address(dsc_Engine), 100 ether);
    //     dsc_Engine.depositCollateralAndMint(weth, 100 ether, userBalance);
    //     stable_coin.approve(address(dsc_Engine), userBalance);
    //     dsc_Engine.liquidate(weth, addr1, userBalance); // We are covering their whole debt
    //     vm.stopPrank();
    // }

    // function testLiquidate() public {
    // // Arrange: Set up the initial conditions and state
    //     uint256 initialCollateral = 10 ether;
    //     uint256 initialMintAmount = 6000 ether;
    //     address user = addr1;
    //     address liquidator = addr2;

    //     // Deposit collateral and mint DSC
    //     vm.startPrank(addr1);
    //     ERC20Mock(weth).approve(address(dsc_Engine), initialCollateral); // Approve tokens
    //     dsc_Engine.depositCollateralAndMint(weth, initialCollateral, initialMintAmount);
    //     vm.stopPrank();

    //     // Act: Simulate a significant drop in ETH price to trigger liquidation
    //     int256 newETHPrice = 100e8; // ETH price drops to $100
    //     MockV3Aggregator(wethUSDPriceFeed).updateAnswer(newETHPrice);

    //     // Verify initial conditions after price drop
    //     (uint256 initialCollateralUSD, uint256 initialDebtUSD) = dsc_Engine.getAccountInfo(user);
    //     console.log("Initial Collateral in USD: ", initialCollateralUSD);
    //     console.log("Initial Debt in USD: ", initialDebtUSD);

    //     // Liquidator deposits collateral to facilitate liquidation
    //     uint256 liquidatorCollateral = 20 ether;
    //     vm.startPrank(liquidator);
    //     ERC20Mock(weth).approve(address(dsc_Engine), liquidatorCollateral); // Approve tokens
    //     dsc_Engine.depositCollateral(weth, liquidatorCollateral);
    //     vm.stopPrank();

    //     // Calculate debt to be recovered and bonus
    //     uint256 debtToRecover = 6000 ether;
    //     uint256 collateralToRecover = dsc_Engine.getTokenAmountFromUSD(weth, debtToRecover);
    //     uint256 bonusCollateral = (collateralToRecover * LIQUIDATION_BONUS) / 100;

    //     // Liquidate the undercollateralized user
    //     vm.startPrank(liquidator);
    //     stable_coin.approve(address(dsc_Engine), debtToRecover); // Approve stable coin
    //     dsc_Engine.liquidate(weth, user, debtToRecover);
    //     vm.stopPrank();

    //     // Verify final conditions after liquidation
    //     (uint256 finalCollateralUSD, uint256 finalDebtUSD) = dsc_Engine.getAccountInfo(user);
    //     console.log("Final Collateral in USD: ", finalCollateralUSD);
    //     console.log("Final Debt in USD: ", finalDebtUSD);

    //     // Assert that the user's debt has been reduced correctly and their debt has been recovered
    //     assertEq(finalDebtUSD, 0, "User's debt should be fully recovered");
    //     assertEq(finalCollateralUSD, initialCollateralUSD - (collateralToRecover + bonusCollateral), "User's collateral should be reduced correctly");
    // }




    // function testMustImproveHealthFactorOnLiquidation() public {
    //     // Arrange - Setup
    //     MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);
    //     tokenAddresses = [weth];
    //     feedAddresses = [ethUsdPriceFeed];
    //     address owner = msg.sender;
    //     vm.prank(owner);
    //     DSCEngine mockDsce = new DSCEngine(tokenAddresses, feedAddresses, address(mockDsc));
    //     mockDsc.transferOwnership(address(mockDsce));
    //     // Arrange - User
    //     vm.startPrank(user);
    //     ERC20Mock(weth).approve(address(mockDsce), amountCollateral);
    //     mockDsce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
    //     vm.stopPrank();

    //     // Arrange - Liquidator
    //     collateralToCover = 1 ether;
    //     ERC20Mock(weth).mint(liquidator, collateralToCover);

    //     vm.startPrank(liquidator);
    //     ERC20Mock(weth).approve(address(mockDsce), collateralToCover);
    //     uint256 debtToCover = 10 ether;
    //     mockDsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
    //     mockDsc.approve(address(mockDsce), debtToCover);
    //     // Act
    //     int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
    //     MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
    //     // Act/Assert
    //     vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
    //     mockDsce.liquidate(weth, user, debtToCover);
    //     vm.stopPrank();
    // }

    


    function testCantLiquidateGoodHealthFactor() public depositCollatarelAndMintDSC(addr1) {
        ERC20Mock(weth).mint(addr2, userBalance);

        vm.startPrank(addr2);
        ERC20Mock(weth).approve(address(dsc_Engine), userBalance);
        dsc_Engine.depositCollateralAndMint(weth, userBalance, 100 ether);
        stable_coin.approve(address(dsc_Engine), 100 ether);

        vm.expectRevert();
        dsc_Engine.liquidate(weth, addr1, 100 ether);
        vm.stopPrank();
    }


    // Health factor and Liquadations test remaining

    
    ///////////////////////
    // Getter Functions ////////
    ///////////////////////

    function getCollatarelInUSD(address user)public view returns(uint256,uint256){
        (uint256 collateral, uint256 debt) = dsc_Engine.getAccountInfo(user);
        // console.log("Collatarel USD: ",collateral/PRECSION);
        uint256 collatarelUSD = collateral/PRECSION;
        uint256 debtUSD = debt/PRECSION;
        return (collatarelUSD,debtUSD);
    }

    function getCollatarelInUSDInWEI(address user)public view returns(uint256,uint256){
        (uint256 collateral, uint256 debt) = dsc_Engine.getAccountInfo(user);
        // console.log("Collatarel USD: ",collateral/PRECSION);
        return (collateral,debt);
    }

    function getValueInUSD(address token, uint256 amount) public view returns(uint256){
        uint256 valueInUsd = dsc_Engine.getValueInUSD(token, amount)/1e18;
        return valueInUsd;
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