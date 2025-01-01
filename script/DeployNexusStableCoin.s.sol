// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {NexusStableCoin} from "../src/NexusStableCoin.sol";

contract DeployNexusStableCoin is Script {
    function run() external returns (NexusStableCoin) {
        vm.startBroadcast();
        NexusStableCoin nexusStableCoin = new NexusStableCoin();
        vm.stopBroadcast();
        return nexusStableCoin;
    }
}
