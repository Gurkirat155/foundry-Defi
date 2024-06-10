// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DeccentralisedStablecoin is ERC20Burnable, Ownable {

    error DeccentralisedStablecoin_ValueMustBeGreaterThanZero();
    error DeccentralisedStablecoin_BalanceShouldBeGreaterThanAmount();

    constructor(address intialOwner) ERC20("DeccentralisedStablecoin", "DSC") Ownable(intialOwner) {}

    function burn(uint256 value) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (value <= 0) {
            revert DeccentralisedStablecoin_ValueMustBeGreaterThanZero();
        }
        if (balance < value) {
            revert DeccentralisedStablecoin_BalanceShouldBeGreaterThanAmount();
        }
        super.burn(value);
    }

    function mint(address to, uint256 value) external onlyOwner returns (bool) {
        if (value <= 0) {
            revert DeccentralisedStablecoin_ValueMustBeGreaterThanZero();
        }
        super._mint(to, value);
        return true;
    }
}
