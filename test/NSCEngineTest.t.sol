// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {NSCEngine} from "../src/NSCEngine.sol";
import {NexusStableCoin} from "../src/NexusStableCoin.sol";
import {DeployNSCEngine} from "../script/DeployNSCEngine.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract NSCEngineTest is Test {
    DeployNSCEngine public deployer;
    NSCEngine public nscEngine;
    NexusStableCoin public nexusStableCoin;
    HelperConfig public helperConfig;
    address weth;
    address wethUsdPriceFeed;

    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployNSCEngine();
        (nexusStableCoin, nscEngine, helperConfig) = deployer.run();
        (wethUsdPriceFeed,, weth,,) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_BALANCE);
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////
    function test_RevertsIfTokenLengthDoesNotMatchPriceFeeds() public {
        address[] memory tokens = new address[](2);
        address[] memory priceFeeds = new address[](1);

        vm.expectRevert(NSCEngine.NSCEngine__TokenAddressesAndPriceFeedAddressesMustBeOfEqualLength.selector);
        new NSCEngine(tokens, priceFeeds, address(nexusStableCoin));
    }

    //////////////////////
    // Price Feed Tests //
    //////////////////////
    function test_GetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = nscEngine.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function test_GetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedTokenAmount = 0.05 ether;
        uint256 actualTokenAmount = nscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualTokenAmount, expectedTokenAmount);
    }

    ////////////////////////
    // depositCollateral //
    ////////////////////////
    function test_RevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(nscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(NSCEngine.NSCEngine__NeedsMoreThanZero.selector);
        nscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function test_RevertItIfTokenNotAllowed() public {
        ERC20Mock ranToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(NSCEngine.NSCEngine__NotAllowedToken.selector);
        nscEngine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_CanDepositCollateralAndGetAccountInfo() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(nscEngine), AMOUNT_COLLATERAL);
        nscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 collateralValue = nscEngine.getAccountCollateralValue(USER);
        uint256 expectedCollateralValue = nscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedCollateralValue);
    }

    /////////////////
    // mintNSC    //
    /////////////////

    function test_MintNSC() public depositedCollateral {
        vm.startPrank(USER);
        nscEngine.mintNSC(AMOUNT_COLLATERAL / 2);

        uint256 userBalance = nexusStableCoin.balanceOf(USER);
        assertEq(userBalance, AMOUNT_COLLATERAL / 2);
    }

    function test_RevertIfMintAmountIsZero() public {
        vm.prank(USER);
        vm.expectRevert(NSCEngine.NSCEngine__NeedsMoreThanZero.selector);
        nscEngine.mintNSC(0);
    }

    function test_RevertIfMintAmountBreaksHealthFactor() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(NSCEngine.NSCEngine__HealthFactorIsBroken.selector, 0));
        nscEngine.mintNSC(AMOUNT_COLLATERAL * 2);
    }

    ////////////////////////
    // redeemCollateral //
    ////////////////////////
    function test_CanRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        nscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 userBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(userBalance, STARTING_BALANCE);
    }

    function test_RevertRedeemCollateralIfAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(NSCEngine.NSCEngine__NeedsMoreThanZero.selector);
        nscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function test_RevertRedeemCollateralIfHealthFactorIsBroken() public depositedCollateral {
        vm.startPrank(USER);
        nscEngine.mintNSC(AMOUNT_COLLATERAL / 2);

        vm.expectRevert(abi.encodeWithSelector(NSCEngine.NSCEngine__HealthFactorIsBroken.selector, 0));
        nscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_CanRedeemCollateralForNSC() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountToMint = AMOUNT_COLLATERAL / 2;
        nscEngine.mintNSC(amountToMint);

        nexusStableCoin.approve(address(nscEngine), amountToMint);
        nscEngine.redeemCollateralForNSC(weth, AMOUNT_COLLATERAL / 2, amountToMint);
        vm.stopPrank();

        uint256 userNscBalance = nexusStableCoin.balanceOf(USER);
        uint256 userCollateralBalance = ERC20Mock(weth).balanceOf(USER);

        assertEq(userNscBalance, 0);
        assertEq(userCollateralBalance, STARTING_BALANCE - (AMOUNT_COLLATERAL / 2));
    }

    function test_RevertRedeemCollateralForNSCIfAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(NSCEngine.NSCEngine__NeedsMoreThanZero.selector);
        nscEngine.redeemCollateralForNSC(weth, 0, 100);
        vm.expectRevert(NSCEngine.NSCEngine__NeedsMoreThanZero.selector);
        nscEngine.redeemCollateralForNSC(weth, 100, 0);
        vm.stopPrank();
    }

    function test_RevertRedeemCollateralForNSCIfHealthFactorIsBroken() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountToMint = AMOUNT_COLLATERAL / 2;
        nscEngine.mintNSC(amountToMint);
        nexusStableCoin.approve(address(nscEngine), amountToMint);

        vm.expectRevert(abi.encodeWithSelector(NSCEngine.NSCEngine__HealthFactorIsBroken.selector, 0));
        nscEngine.redeemCollateralForNSC(weth, AMOUNT_COLLATERAL, amountToMint / 2);
        vm.stopPrank();
    }

    function test_RevertRedeemCollateralForNSCIfNotEnoughNSC() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountToMint = AMOUNT_COLLATERAL / 4;
        nscEngine.mintNSC(amountToMint);
        nexusStableCoin.approve(address(nscEngine), amountToMint);

        vm.expectRevert(NSCEngine.NSCEngine__BurnAmountExceedsBalance.selector);
        nscEngine.redeemCollateralForNSC(weth, AMOUNT_COLLATERAL / 2, amountToMint * 2);
        vm.stopPrank();
    }

    //////////////
    // Burn NSC //
    //////////////
    function test_CanBurnNSC() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountToMint = AMOUNT_COLLATERAL / 2;
        nscEngine.mintNSC(amountToMint);

        nexusStableCoin.approve(address(nscEngine), amountToMint);
        nscEngine.burnNSC(amountToMint);
        vm.stopPrank();

        uint256 userBalance = nexusStableCoin.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    function test_RevertBurnNSCIfAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(NSCEngine.NSCEngine__NeedsMoreThanZero.selector);
        nscEngine.burnNSC(0);
        vm.stopPrank();
    }

    function test_RevertBurnNSCIfAmountExceedsBalance() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountToMint = AMOUNT_COLLATERAL / 2;
        nscEngine.mintNSC(amountToMint);

        nexusStableCoin.approve(address(nscEngine), amountToMint);
        vm.expectRevert(NSCEngine.NSCEngine__BurnAmountExceedsBalance.selector);
        nscEngine.burnNSC(amountToMint + 1);
        vm.stopPrank();
    }

    ///////////////
    // Modifiers //
    ///////////////

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(nscEngine), AMOUNT_COLLATERAL);
        nscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }
}
