// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {console}  from "forge-std/console.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeccentralisedStablecoin} from "../../src/Stablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

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
    uint256 constant public userCollatarel = 20 ether;
    uint256 constant public userBalance = 20 ether;


    
    function setUp() public {
        deployDSC = new DeployDSC();
        ( stable_coin,  dsc_Engine , helper_Config) = deployDSC.run();

        ( wethUSDPriceFeed,  wbtcUSDPriceFeed,  weth,  wbtc, deployerKey) =
            helper_Config.activeConfig();
        vm.deal(addr1,userBalance);
        ERC20Mock(weth).mint(addr1,userCollatarel);
    }

    function checkMsgsender(address msgSender, address comparedAddress) public pure returns(bool){
        return msgSender == comparedAddress;
    }

    function testOwnerOfStableCoin() public view {
        address owner = stable_coin.owner();
        assertEq(owner, address(dsc_Engine),"Owner should be DSCEngine");
    }

    function testCheckOwnerBal() public view  returns(uint256){
        // vm.prank(dsc_Engine);
        uint256 bal = stable_coin.balanceOf(address(dsc_Engine));
        uint256 totalSupply = stable_coin.totalSupply();
        console.log("Balance of DSCEngine: ", bal);
        console.log("Total Supply of DSC: ", totalSupply);
        assertEq(bal,totalSupply);
        return bal;
    }

    // Deposit function testing

    function testRevertIfCollateralIsZero() public {
        vm.expectRevert(DSCEngine.DSCEngine_ValueMustBeGreaterThanZero.selector);
        dsc_Engine.depositCollateral(weth,0);
    }

    // function testMintingFunction() public {
    //     // console.log(weth);
    //     dsc_Engine.depositCollateral(weth, 1000);
    //     dsc_Engine.mintDSC(1000);
    //     // stable_coin.mint(address(dsc_Engine),1000);
    //     // console.log(stable_coin.totalSupply());
    //     // assertEq(testCheckOwnerBal(), 1000);
    // }

    // function testDepositCollateral() public {
    //     dsc_Engine.depositCollateral(weth, 1000);
    //     console.log()
    // }
}