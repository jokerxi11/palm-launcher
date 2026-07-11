// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";

/// @title PalmLauncher
/// @author PalmLauncher
/// @notice Generic, single-call Uniswap V2 liquidity launcher. Works with ANY standard ERC20
///         token, not just one specific token.
/// @dev The launcher is completely stateless and permissionless. It never takes custody of
///      tokens or ETH beyond the lifetime of a single `launch()` call, and it never receives
///      admin rights over deployed pairs or over the tokens it launches. Anyone can call
///      `launch()` for any token they hold and have approved.
///
///      A single call to `launch()`:
///        1. Pulls `tokenAmount` of `tokenAddress` from the caller (requires prior approval).
///        2. Approves the Uniswap V2 Router to spend those tokens.
///        3. Calls `Router.addLiquidityETH`, which itself, atomically:
///             - creates the Token/WETH pair via the Factory if it does not already exist,
///             - wraps the attached ETH into WETH,
///             - adds both sides as liquidity at the current (or initial) pool ratio,
///             - mints LP tokens directly to `recipient`.
///        4. Refunds any leftover tokens/ETH (from Uniswap's optimal-ratio rounding) to the caller.
///        5. Emits a `Launched` event with the resolved pair address and amounts used.
contract PalmLauncher is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The Uniswap V2 Router used for all liquidity operations.
    IUniswapV2Router02 public immutable router;

    /// @notice The Uniswap V2 Factory associated with `router`.
    IUniswapV2Factory public immutable factory;

    /// @notice Emitted after a successful launch.
    /// @param token The token that was launched.
    /// @param pair The resolved Token/WETH Uniswap V2 pair address.
    /// @param recipient The address that received the minted LP tokens.
    /// @param tokenAmountUsed The amount of token actually deposited into the pool.
    /// @param ethAmountUsed The amount of ETH actually deposited into the pool.
    /// @param lpTokensReceived The amount of LP tokens minted to `recipient`.
    event Launched(
        address indexed token,
        address indexed pair,
        address indexed recipient,
        uint256 tokenAmountUsed,
        uint256 ethAmountUsed,
        uint256 lpTokensReceived
    );

    error ZeroAddress();
    error ZeroAmount();
    error ZeroEth();
    error EthRefundFailed();

    /// @param _router Address of the Uniswap V2 Router02 (or fully compatible fork) contract.
    constructor(address _router) {
        if (_router == address(0)) revert ZeroAddress();
        router = IUniswapV2Router02(_router);
        factory = IUniswapV2Factory(router.factory());
    }

    /// @notice Launches liquidity for `tokenAddress`, pairing it with the attached ETH.
    /// @dev Caller must have called `IERC20(tokenAddress).approve(address(this), tokenAmount)`
    ///      (or higher) before calling this function.
    ///
    ///      Slippage note: `amountTokenMin` / `amountETHMin` passed to the router are both zero.
    ///      This is intentional and safe for a *brand-new* pool (the first liquidity add sets the
    ///      price, so there is nothing to be sandwiched against). If `tokenAddress` is paired with
    ///      WETH and already has existing liquidity, calling this again is exposed to price
    ///      movement/front-running like any zero-slippage-protection liquidity add — only launch
    ///      a token's *initial* liquidity through this function, or add liquidity with slippage
    ///      protection directly via the Router afterwards.
    /// @param tokenAddress The ERC20 token to launch.
    /// @param tokenAmount The amount of tokens to add as liquidity.
    /// @param recipient The address that will receive the minted LP tokens.
    function launch(
        address tokenAddress,
        uint256 tokenAmount,
        address recipient
    ) external payable nonReentrant {
        if (tokenAddress == address(0) || recipient == address(0)) revert ZeroAddress();
        if (tokenAmount == 0) revert ZeroAmount();
        if (msg.value == 0) revert ZeroEth();

        IERC20 token = IERC20(tokenAddress);

        // 1. Pull tokens from caller (caller must have approved this contract beforehand).
        token.safeTransferFrom(msg.sender, address(this), tokenAmount);

        // 2. Approve the router to pull the tokens back out for the liquidity add.
        token.forceApprove(address(router), tokenAmount);

        // 3. Add liquidity. The router internally creates the pair (if needed) and wraps ETH.
        (uint256 tokenUsed, uint256 ethUsed, uint256 lpTokens) = router.addLiquidityETH{
            value: msg.value
        }(
            tokenAddress,
            tokenAmount,
            0, // amountTokenMin -- see slippage note in NatSpec above
            0, // amountETHMin -- see slippage note in NatSpec above
            recipient,
            block.timestamp
        );

        // 4. Clear any residual approval (routers should consume it fully, but don't trust that).
        token.forceApprove(address(router), 0);

        // 5. Refund unused tokens to the caller.
        uint256 tokenLeftover = tokenAmount - tokenUsed;
        if (tokenLeftover > 0) {
            token.safeTransfer(msg.sender, tokenLeftover);
        }

        // 6. Refund unused ETH to the caller.
        uint256 ethLeftover = msg.value - ethUsed;
        if (ethLeftover > 0) {
            (bool sent, ) = msg.sender.call{value: ethLeftover}("");
            if (!sent) revert EthRefundFailed();
        }

        address pair = factory.getPair(tokenAddress, router.WETH());

        emit Launched(tokenAddress, pair, recipient, tokenUsed, ethUsed, lpTokens);
    }

    /// @notice Rejects stray ETH sent outside of `launch()`.
    receive() external payable {
        revert("PalmLauncher: direct ETH not accepted");
    }
}
