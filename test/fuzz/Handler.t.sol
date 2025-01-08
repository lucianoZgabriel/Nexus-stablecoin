// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {NSCEngine} from "../../src/NSCEngine.sol";
import {NexusStableCoin} from "../../src/NexusStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    NSCEngine public nscEngine;
    NexusStableCoin public nexusStableCoin;
    ERC20Mock public weth;
    ERC20Mock public wbtc;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 public constant MAX_DEPOSIT_SIZE = 1e6 * 1e18;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;

    uint256 public timesMintIsCalled;

    mapping(address => bool) public hasValidCollateral;
    address[] public usersWithCollateralDeposited;

    constructor(NSCEngine _nscEngine, NexusStableCoin _nexusStableCoin) {
        nscEngine = _nscEngine;
        nexusStableCoin = _nexusStableCoin;

        address[] memory collateralTokens = nscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
        ethUsdPriceFeed = MockV3Aggregator(nscEngine.getCollateralTokenPriceFeed(address(weth)));
    }

    function mintNsc(uint256 amountSeed, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) return;
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        if (!hasValidCollateral[sender]) return;

        (uint256 totalNscMinted, uint256 totalCollateralValueInUsd) = nscEngine.getAccountInformation(sender);

        uint256 maxNscMintable = (totalCollateralValueInUsd * 50) / 100;
        if (maxNscMintable == 0) return;

        uint256 amountToMint = bound(amountSeed, 0, maxNscMintable - totalNscMinted);
        if (amountToMint == 0) return;

        vm.startPrank(sender);
        nscEngine.mintNSC(amountToMint);
        timesMintIsCalled++;
        vm.stopPrank();
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountSeed) public {
        uint256 boundedCollateralSeed = bound(collateralSeed, 0, 1);
        ERC20Mock collateral = _getCollateralFromSeed(boundedCollateralSeed);
        uint256 amount = bound(amountSeed, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(nscEngine), amount);
        try nscEngine.depositCollateral(address(collateral), amount) {
            hasValidCollateral[msg.sender] = true;
            usersWithCollateralDeposited.push(msg.sender);
        } catch {
            hasValidCollateral[msg.sender] = false;
        }
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        if (!hasValidCollateral[msg.sender]) return;

        uint256 boundedCollateralSeed = bound(collateralSeed, 0, 1);
        ERC20Mock collateral = _getCollateralFromSeed(boundedCollateralSeed);
        uint256 maxCollateral = collateral.balanceOf(address(nscEngine));
        if (maxCollateral == 0) return;

        uint256 userCollateralBalance = nscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        if (userCollateralBalance == 0) return;

        uint256 amountToRedeem = bound(amountCollateral, 0, min(maxCollateral, userCollateralBalance));
        if (amountToRedeem == 0) return;

        vm.startPrank(msg.sender);
        try nscEngine.redeemCollateral(address(collateral), amountToRedeem) {
            uint256 remainingCollateral = nscEngine.getAccountCollateralValue(msg.sender);
            hasValidCollateral[msg.sender] = remainingCollateral > 0;
        } catch {
            hasValidCollateral[msg.sender] = false;
        }
        vm.stopPrank();
    }

    // This test breaks the fuzzing
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    function _getCollateralFromSeed(uint256 collateralSeed) internal view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
