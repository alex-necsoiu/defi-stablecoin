// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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

/*
 * @title Decentralized Stable Coin
 * @author Alex Necsoiu
 * Colateral: Exogenus (ETH & BTC)
 * Minting: Algorithmic (Decentralized)
 * Relative Stability: Anchored or Pegged -> $1.00
 *
 * This contract meat to be governed by the DSCEngine contract.
 * This contract is just the ERC20 implementation of the Decentralized Stable Coin (DSC).
 */
import {ERC20Burnable, ERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    ///////////////////
    // Errors	     //
    ///////////////////
    error DecentralizedStableCoin__MustBeMoreThanZero(); // Fixed typo
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor()
        ERC20("Decentralized Stable Coin", "DSC")
        Ownable(msg.sender)
    {}

    /**
     * Burn DSC tokens from the caller's account.
     * @param _amount The amount of tokens to burn.
     * @notice This function allows the owner to burn a specified amount of DSC tokens from their
     */
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero(); // Fixed typo
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }

        // Call the parent burn function from ERC20Burnable
        super.burn(_amount);
    }
    /**
     * Mint DSC tokens to a specified address.
     * @param _to The address to mint tokens to.
     * @param _amount The amount of tokens to mint.
     * @return bool indicating success of the operation.
     */
    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero(); // Fixed typo
        }
        _mint(_to, _amount);
        return true;
    }
}
