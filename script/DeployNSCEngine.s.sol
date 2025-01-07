// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {NexusStableCoin} from "../src/NexusStableCoin.sol";
import {NSCEngine} from "../src/NSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployNSCEngine is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (NexusStableCoin, NSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        NexusStableCoin nexusStableCoin = new NexusStableCoin();
        NSCEngine nscEngine = new NSCEngine(tokenAddresses, priceFeedAddresses, address(nexusStableCoin));
        nexusStableCoin.transferOwnership(address(nscEngine));
        vm.stopBroadcast();

        return (nexusStableCoin, nscEngine, helperConfig);
    }
}
