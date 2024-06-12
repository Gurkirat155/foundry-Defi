// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DeccentralisedStablecoin} from "../src/Stablecoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    DeccentralisedStablecoin stablecoin;
    DSCEngine dscEngine;

    // ETH 0x694AA1769357215DE4FAC081bf1f309aDC325306 PRICE IN USD
    // BTC 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43 PRICE IN USD
    function run() external returns (DeccentralisedStablecoin, DSCEngine) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUSDPriceFeed, address wbtcUSDPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeConfig();

        vm.startBroadcast();
        stablecoin = new DeccentralisedStablecoin(msg.sender);
        dscEngine = new DSCEngine([weth, wbtc], [wethUSDPriceFeed, wbtcUSDPriceFeed], address(stablecoin));
        stablecoin.transferOwnership(address(dscEngine));
        vm.stopBroadcast();
        
        return (stablecoin, dscEngine);
    }
}
