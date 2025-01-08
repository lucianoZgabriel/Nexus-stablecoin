// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {NSCEngine} from "../../src/NSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {NexusStableCoin} from "../../src/NexusStableCoin.sol";
import {DeployNSCEngine} from "../../script/DeployNSCEngine.s.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Handler} from "./Handler.t.sol";
import {console} from "forge-std/console.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployNSCEngine deployer;
    NSCEngine nscEngine;
    NexusStableCoin nsc;
    HelperConfig helperConfig;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployNSCEngine();
        (nsc, nscEngine, helperConfig) = deployer.run();
        (,, weth, wbtc,) = helperConfig.activeNetworkConfig();
        handler = new Handler(nscEngine, nsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHavenMoreValueThanTotalSupply() public view {
        uint256 totalSupply = nsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(nscEngine));
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(nscEngine));

        uint256 wethValue = nscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 btcValue = nscEngine.getUsdValue(wbtc, totalBtcDeposited);

        uint256 totalCollateralValue = wethValue + btcValue;

        console.log("wethValue: %s", wethValue);
        console.log("wbtcValue: %s", btcValue);
        console.log("Total Supply: %s", totalSupply);
        console.log("Times mint is called: %s", handler.timesMintIsCalled());
        assert(totalCollateralValue >= totalSupply);
    }
}
