// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Token
/// @author PalmLauncher
/// @notice Minimal, fixed-supply, fully standard ERC20 token.
/// @dev Deliberately kept as simple as possible:
///      - No mint function (supply is fixed forever after construction)
///      - No burn function
///      - No taxes, no blacklist, no whitelist, no anti-bot, no cooldown
///      - No transfer delay, no max wallet, no max tx
///      - No trading-enable switch, no pair storage
///      - No proxy / upgradeability / delegatecall
///      - No hidden owner permissions
///
///      The ONLY privileged action available to the owner is rescuing foreign ERC20 tokens that
///      were accidentally sent to this contract. The owner has no power whatsoever over this
///      token's own supply, balances, or transferability.
contract Token is ERC20, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Thrown when the owner attempts to rescue this token's own balance.
    error CannotRescueSelf();

    /// @param name_ The ERC20 name.
    /// @param symbol_ The ERC20 symbol.
    /// @param totalSupply_ The total supply to mint, denominated in the token's smallest unit
    ///        (i.e. already scaled by `decimals()`). This entire amount is minted once to `owner_`.
    /// @param owner_ The initial owner and sole recipient of the total supply.
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        address owner_
    ) ERC20(name_, symbol_) Ownable(owner_) {
        _mint(owner_, totalSupply_);
    }

    /// @notice Rescues ERC20 tokens accidentally sent directly to this contract.
    /// @dev Cannot be used to rescue this token's own balance, which would otherwise let the
    ///      owner circumvent the fixed-supply guarantee by draining tokens held by the contract
    ///      itself (e.g. tokens mistakenly sent to the token contract's own address).
    /// @param token The foreign ERC20 token to rescue.
    /// @param to The recipient of the rescued tokens.
    /// @param amount The amount to rescue.
    function rescueERC20(IERC20 token, address to, uint256 amount) external onlyOwner {
        if (address(token) == address(this)) revert CannotRescueSelf();
        token.safeTransfer(to, amount);
    }
}
