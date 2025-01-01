// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title NexusStableCoin
 * @author Luciano Zanin Gabriel
 * Collateral: Exogenous (ETH and BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 *
 * This is the contract meant to be governed by NexusEngine. This is just the ERC20 implementation of the NexusStableCoin.
 */
contract NexusStableCoin is ERC20Burnable, Ownable {
    error NexusStableCoin__MustBeMoreThanZero();
    error NexusStableCoin__BurnAmountExceedsBalance();
    error NexusStableCoin__MustBeAValidAddress();

    constructor() ERC20("NexusStableCoin", "NSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) revert NexusStableCoin__MustBeMoreThanZero();
        if (balance < _amount)
            revert NexusStableCoin__BurnAmountExceedsBalance();
        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) revert NexusStableCoin__MustBeAValidAddress();
        if (_amount <= 0) revert NexusStableCoin__MustBeMoreThanZero();
        _mint(_to, _amount);
        return true;
    }
}
