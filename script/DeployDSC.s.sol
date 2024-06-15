// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DeccentralisedStablecoin} from "../src/Stablecoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    DeccentralisedStablecoin stablecoin;
    DSCEngine dscEngine;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    // ETH 0x694AA1769357215DE4FAC081bf1f309aDC325306 PRICE IN USD
    // BTC 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43 PRICE IN USD
    function run() external returns (DeccentralisedStablecoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUSDPriceFeed, address wbtcUSDPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUSDPriceFeed, wbtcUSDPriceFeed];

        vm.startBroadcast(deployerKey);
        stablecoin = new DeccentralisedStablecoin(msg.sender);
        dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(stablecoin));
        console.log(stablecoin.balanceOf(msg.sender));
        vm.stopBroadcast();

        address owner = stablecoin.owner();
        vm.prank(owner);
        stablecoin.transferOwnership(address(dscEngine));
        vm.stopPrank();

        return (stablecoin, dscEngine, helperConfig);
    }
}
