// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title NSCEngine
 * @author Luciano Zanin Gabriel
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar pegged
 * - Algoritmically stable
 *
 * It is similar to DAI, but with a few key differences:
 * - No governance
 * - No fees
 * - Only backed by WETH and WBTC
 *
 * Our NSC system should always be over-collateralized. This means that the total value of the collateral should always be greater than the total value of the NSC.
 *
 * @notice This contract is the core of the NSC System. It handles all the logic for minting and burning NSC, as well asa depositing and withdrawing collateral.
 * @notice This contract is loosely based on the MakerDAO DSS system.
 */
contract NSCEngine {
    function depositCollateralAndMint() external {}

    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) external {}

    function redeemCollateralforNSC() external {}

    function redeemCollateral() external {}

    function mintNSC() external {}

    function burnNSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
