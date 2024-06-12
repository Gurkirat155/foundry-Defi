// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockAggregator.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUSDPriceFeed;
        address wbtcUSDPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    int256 public constant intialWethUSDPrice = 3400e8;
    int256 public constant intialWbtcUSDPrice = 67191e8;
    uint8 public constant decimals = 8;
    MockERC20 public mockWethERC20;
    MockERC20 public mockWbtcERC20;
    MockV3Aggregator public wethPriceFeed;
    MockV3Aggregator public wbtcPriceFeed;

    NetworkConfig public activeConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeConfig = getSepoliaEthConfig();
        } else if (block.chainid == 31337) {
            activeConfig = getOrCreateAnvilConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        NetworkConfig memory config = NetworkConfig({
            wethUSDPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUSDPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("SEPOLIA_PRIVATE_KEY")
        });
        return config;
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        // if (activeConfig.wethUSDPriceFeed != address(0) && activeConfig.wbtcUSDPriceFeed != address(0)) {
        //     return activeConfig;
        // }

        vm.startBroadcast();
        wethPriceFeed = new MockV3Aggregator(decimals, intialWethUSDPrice);
        wbtcPriceFeed = new MockV3Aggregator(decimals, intialWbtcUSDPrice);
        mockWethERC20 = new MockERC20();
        mockWbtcERC20 = new MockERC20();
        mockWethERC20.initialize("WETH", "WETH", decimals);
        mockWbtcERC20.initialize("WBTC", "WBTC", decimals);
        vm.stopBroadcast();

        NetworkConfig memory config = NetworkConfig({
            wethUSDPriceFeed: address(wethPriceFeed),
            wbtcUSDPriceFeed: address(wbtcPriceFeed),
            weth: address(mockWethERC20),
            wbtc: address(mockWbtcERC20),
            deployerKey: vm.envUint("ANVIL_PRIVATE_KEY")
        });

        return config;
    }
}

// Mainnet
// weth - 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
// wbtc - 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c

// SEPOLIA
// weth - 0x694AA1769357215DE4FAC081bf1f309aDC325306
// wbtc - 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43
