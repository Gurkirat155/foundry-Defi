// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockAggregator} from "../test/mocks/MockAggregator.sol";
import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUSDPriceFeed;
        address wbtcUSDPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    uint256 public constant intialWethUSDPrice = 3400e8;
    uint256 public constant intialWbtcUSDPrice = 67191e8;
    uint256 public constant decimals = 8;
    MockERC20 public mockWethERC20;
    MockERC20 public mockWbtcERC20;
    MockAggregator public wethPriceFeed;
    MockAggregator public wbtcPriceFeed;

    NetworkConfig public activeConfig;

    constructor() {
        if (block.chainId == 11155111) {
            activeConfig = getSepoliaEthConfig();
        } else if (block.chainId == 31337) {
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

    function getOrCreateAnvilConfig() public view returns (NetworkConfig memory) {
        if (activeConfig.priceFeed != address(0)) {
            return activeConfig;
        }

        vm.startBroadcast();
        wethPriceFeed = new MockAggregator(intialWethUsdPrice, decimals);
        // mockWethERC20 = new MockERC20("WETH", "WETH", decimals);
        mockWethERC20 = new MockERC20();
        mockWbtcERC20 = new MockERC20();
        mockWethERC20.initialize("WETH", "WETH", decimals);
        mockWbtcERC20.initialize("WBTC", "WBTC", decimals);
        wbtcPriceFeed = new MockAggregator(intialWbtcUSDPrice, decimals);
        vm.stopBroadcast();

        NetworkConfig memory config = NetworkConfig({
            wethUSDPriceFeed: wethPriceFeed,
            wbtcUSDPriceFeed: wbtcPriceFeed,
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
