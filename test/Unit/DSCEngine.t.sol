// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test ,console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeccentralisedStablecoin} from "../../src/Stablecoin.sol";

contract TestingDSCEngine is Test,console {

    DSCEngine dsc_Engine;
    DeccentralisedStablecoin stable_coin;
    DeployDSC deployDSC;
    
    function run() public {
        deployDSC = new DeployDSC();
        (address stablecoin, address dscEngine) = deployDSC.run();

        console.log((stable_coin), (dsc_Engine));
        stable_coin = stablecoin;
        dsc_Engine = dscEngine;
    }

    function testAddress() public view {
        // console.log(stablecoin, dscEngine);
        console.log(address(stable_coin), address(dsc_Engine));
    }
}