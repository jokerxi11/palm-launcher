// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PalmLauncher} from "../src/PalmLauncher.sol";
import {IUniswapV2Factory} from "../src/interfaces/IUniswapV2Factory.sol";

/// @notice TRANSACTION 2: approves the launcher and launches liquidity for TOKEN_ADDRESS.
/// @dev This script broadcasts two calls from the same EOA (approve + launch) because the token
///      is a fully standard ERC20 with no `permit()` -- by design, per project spec, the token
///      contract stays minimal with no extra EIP-2612 surface. If you want a single raw
///      transaction instead of a two-call script, add EIP-2612 permit support to Token.sol and
///      have the launcher accept a permit signature; that is intentionally left out here to keep
///      the token as simple as possible.
///
///      Run with:
///      forge script script/Launch.s.sol:Launch --rpc-url $RPC_URL --broadcast
contract Launch is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        address launcherAddress = vm.envAddress("LAUNCHER_ADDRESS");
        address router = vm.envAddress("ROUTER");
        address factory = vm.envAddress("FACTORY");
        address weth = vm.envAddress("WETH");
        uint256 tokenAmount = vm.envUint("TOKEN_AMOUNT");
        uint256 ethAmount = vm.envUint("ETH_AMOUNT");
        address recipient = vm.envAddress("RECIPIENT");

        PalmLauncher launcher = PalmLauncher(launcherAddress);
        IERC20 token = IERC20(tokenAddress);

        // ---- Pre-flight validation ----
        require(address(launcher.router()) == router, "ROUTER mismatch vs launcher.router()");
        require(launcher.router().WETH() == weth, "WETH mismatch vs router.WETH()");
        require(address(launcher.factory()) == factory, "FACTORY mismatch vs launcher.factory()");
        require(tokenAddress != address(0), "TOKEN_ADDRESS is zero");
        require(recipient != address(0), "RECIPIENT is zero");
        require(tokenAmount > 0, "TOKEN_AMOUNT must be > 0");
        require(ethAmount > 0, "ETH_AMOUNT must be > 0");
        require(token.balanceOf(deployer) >= tokenAmount, "Insufficient token balance");
        require(deployer.balance >= ethAmount, "Insufficient ETH balance");

        vm.startBroadcast(deployerKey);

        // Approve the launcher to pull the tokens.
        token.approve(address(launcher), tokenAmount);

        // Launch: internally wraps ETH, creates the pair if needed, adds liquidity, sends LP to
        // `recipient`, and refunds any leftover tokens/ETH to the deployer.
        launcher.launch{value: ethAmount}(tokenAddress, tokenAmount, recipient);

        vm.stopBroadcast();

        // ---- Post-launch reporting ----
        address pair = IUniswapV2Factory(factory).getPair(tokenAddress, weth);
        uint256 lpBalance = IERC20(pair).balanceOf(recipient);

        console.log("================ TOKEN LAUNCHED ================");
        console.log("Token:        ", tokenAddress);
        console.log("Pair:         ", pair);
        console.log("Router:       ", router);
        console.log("Factory:      ", factory);
        console.log("Recipient:    ", recipient);
        console.log("LP Balance:   ", lpBalance);
        console.log("ETH Sent:     ", ethAmount);
        console.log("Tokens Sent:  ", tokenAmount);
        console.log("==================================================");
        console.log("Gas used and the transaction hash are printed by forge in the broadcast");
        console.log("summary above, and saved to broadcast/Launch.s.sol/<chainId>/run-latest.json");
    }
}
