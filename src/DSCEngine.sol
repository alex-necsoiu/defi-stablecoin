//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
* @title Decentralized Stable Coin Engine
* @author Alex Necsoiu
*
* The system is designed to to be as minimal as possible, and have the tokens maintain a 1 token == $1.00 USD peg.
* This stablecoin has the properties:
* - Exogenous Collateral: Backed by ETH and BTC.
* - Dollar Pegged: The stablecoin is pegged to the US Dollar.
* - Algoritmically Stable
* It is similar to DAI if DAI had no governance, no fees, and only backed by WETH and WBTC.
*
* @notice This contract is the engine of the DSC System. It handles all the logic for the minting and redeeming DSC, as well as depositing & withdrawing collateral.
* @notice This contract is based on the MakerDAO DSS (DAI) system.
 */

 contract DSCEngine {
	function depositCollateralAndMintDsc()external{}
	function redeemCollateralForDsc()external{}
	function burnDesc() external {}
		
 }