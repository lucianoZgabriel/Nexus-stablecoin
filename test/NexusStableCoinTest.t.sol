// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {NexusStableCoin} from "../src/NexusStableCoin.sol";
import {DeployNexusStableCoin} from "../script/DeployNexusStableCoin.s.sol";

contract NexusStableCoinTest is Test {
    NexusStableCoin public nexusStableCoin;
    DeployNexusStableCoin public deployer;
    address public owner;
    address public user = makeAddr("user");

    uint256 public constant STARTING_BALANCE = 100 ether;
    uint256 public constant MINT_AMOUNT = 10 ether;
    uint256 public constant BURN_AMOUNT = 5 ether;

    function setUp() public {
        deployer = new DeployNexusStableCoin();
        nexusStableCoin = deployer.run();
        owner = msg.sender;
    }

    function test_ConstructorSetsNameAndSymbol() public view {
        assertEq(nexusStableCoin.name(), "NexusStableCoin");
        assertEq(nexusStableCoin.symbol(), "NSC");
    }

    // Minting

    function test_MintSuccessfully() public {
        vm.prank(owner);
        bool success = nexusStableCoin.mint(user, MINT_AMOUNT);
        assertTrue(success);
        assertEq(nexusStableCoin.balanceOf(user), MINT_AMOUNT);
    }

    function testFail_MintByNonOwner() public {
        vm.prank(user);
        nexusStableCoin.mint(user, MINT_AMOUNT);
    }

    function test_RevertMint_WhenMintingToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(
            NexusStableCoin.NexusStableCoin__MustBeAValidAddress.selector
        );
        nexusStableCoin.mint(address(0), MINT_AMOUNT);
    }

    function test_RevertMint_WhenMintingZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(
            NexusStableCoin.NexusStableCoin__MustBeMoreThanZero.selector
        );
        nexusStableCoin.mint(user, 0);
    }

    // Burning

    function test_BurnSuccessfully() public {
        vm.startPrank(owner);
        nexusStableCoin.mint(owner, MINT_AMOUNT);
        uint256 ownerBalanceBefore = nexusStableCoin.balanceOf(owner);

        nexusStableCoin.burn(BURN_AMOUNT);
        assertEq(
            nexusStableCoin.balanceOf(owner),
            ownerBalanceBefore - BURN_AMOUNT
        );
        vm.stopPrank();
    }

    function testFail_BurnByNonOwner() public {
        vm.prank(user);
        nexusStableCoin.burn(BURN_AMOUNT);
    }

    function test_RevertBurn_WhenBurningZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(
            NexusStableCoin.NexusStableCoin__MustBeMoreThanZero.selector
        );
        nexusStableCoin.burn(0);
    }

    function test_RevertBurn_WhenBurningMoreThanBalance() public {
        vm.startPrank(owner);
        nexusStableCoin.mint(owner, STARTING_BALANCE);
        vm.expectRevert(
            NexusStableCoin.NexusStableCoin__BurnAmountExceedsBalance.selector
        );
        nexusStableCoin.burn(STARTING_BALANCE + 1);
        vm.stopPrank();
    }
}
