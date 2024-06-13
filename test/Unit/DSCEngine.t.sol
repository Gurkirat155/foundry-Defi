// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {console}  from "forge-std/console.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeccentralisedStablecoin} from "../../src/Stablecoin.sol";

contract TestingDSCEngine is Test {

    DSCEngine dsc_Engine;
    DeccentralisedStablecoin stable_coin;
    DeployDSC deployDSC;
    
    function setUp() public {
        deployDSC = new DeployDSC();
        ( stable_coin,  dsc_Engine) = deployDSC.run();
    }

    function testOwner() public view {
        address owner = stable_coin.owner();
        assertEq(owner, address(dsc_Engine),"Owner should be DSCEngine");
    }
}