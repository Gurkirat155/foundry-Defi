// this will have our invariants whoes properties will hold true

// Invariants

// 1. Total supply of dsc should be less than collatarel

// 2. getter view function should never revert

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeccentralisedStablecoin} from "../../src/Stablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../Mocks/MockERC20.sol";

contract InvariantsTest is StdInvariant, Test {
    DSCEngine dsc_Engine;
    DeccentralisedStablecoin stable_Coin;
    HelperConfig helperConfig;
    DeployDSC deployDSC;

    address wethUSDPriceFeed;
    address wbtcUSDPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;

    address addr1 = makeAddr("user1");
    address addr2 = makeAddr("user2");
    uint256 public constant userCollatarel = 10 ether;
    uint256 public constant userBalance = 20 ether;

    function setUp() public {
        deployDSC = new DeployDSC();
        (stable_Coin, dsc_Engine, helperConfig) = deployDSC.run();

        (wethUSDPriceFeed, wbtcUSDPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeConfig();

        // if (block.chainid == 31337) {
        //      vm.deal(addr1, userBalance);
        // }

        ERC20Mock(weth).mint(addr1, userCollatarel);
        ERC20Mock(wbtc).mint(addr1, userCollatarel);

        targetContract(address(dsc_Engine));
    }

    function invariant_protocolMusthaveMorevalueThanTotalSupply() public view {
        uint256 totalWethDeposited = ERC20Mock(weth).totalSupply();
        uint256 totalWbtcDeposited = ERC20Mock(wbtc).totalSupply();
        // uint256 wethValue = dsc_Engine.getValueInUSD(weth, userCollatarel);
        // uint256 wbtcValue = dsc_Engine.getValueInUSD(wbtc, userCollatarel);
        uint256 totalSupply = stable_Coin.totalSupply();

        console.log("Total Supply: ", totalSupply);
        console.log("Weth Value: ", totalWethDeposited);
        console.log("Wbtc Value: ", totalWbtcDeposited);

        assert(totalWethDeposited + totalWbtcDeposited >= totalSupply);
    }
}
