# Palm Launcher

A minimal, audit-friendly Foundry project for launching a fixed-supply ERC20 token on Uniswap V2
(or any Uniswap V2-compatible fork, including Robinhood Chain) in as few manual steps as possible.

## Design philosophy

The **token** and the **launch mechanics** are deliberately kept in two completely separate
contracts:

- **`Token.sol`** — a plain, standard, fixed-supply ERC20. No taxes, no admin switches, no
  upgradeability. The only owner privilege is rescuing foreign ERC20 tokens accidentally sent to
  the contract. It has nothing to do with Uniswap and knows nothing about pairs, routers, or
  liquidity.
- **`PalmLauncher.sol`** — a generic, stateless, permissionless launcher that works with **any**
  standard ERC20, not just this one. It pulls tokens + ETH from the caller in a single call,
  creates the Uniswap V2 pair if needed, adds liquidity, and sends the LP tokens to whoever you
  specify.

This separation means the token contract stays as small and easy to audit as possible, while all
the launch complexity lives in a contract you can reuse for every future token you launch — you
only ever deploy `PalmLauncher` once per chain.

## Contracts

| File | Purpose |
|---|---|
| `src/Token.sol` | Standard fixed-supply ERC20 (OpenZeppelin v5) |
| `src/PalmLauncher.sol` | Generic Uniswap V2 liquidity launcher for any ERC20 |
| `src/interfaces/IUniswapV2Router02.sol` | Minimal Router02 interface |
| `src/interfaces/IUniswapV2Factory.sol` | Minimal Factory interface |
| `src/interfaces/IWETH.sol` | Minimal WETH interface |
| `src/interfaces/IERC20.sol` | Re-export of OpenZeppelin's IERC20 |
| `script/DeployToken.s.sol` | Transaction 1 — deploys the token |
| `script/DeployLauncher.s.sol` | One-time-per-chain launcher deployment |
| `script/Launch.s.sol` | Transaction 2 — approves + launches liquidity |
| `test/PalmLauncher.t.sol` | Fork tests against real mainnet Uniswap V2 |

## How the "two transactions" work

1. **Deploy the launcher once per chain** with `DeployLauncher.s.sol`. This is infrastructure, not
   part of any individual token launch — after this one-time step, every future token launch on
   that chain only needs the two steps below.
2. **Transaction 1 — `DeployToken.s.sol`**: deploys your token, minting the entire fixed supply to
   the owner you specify.
3. **Transaction 2 — `Launch.s.sol`**: approves the launcher for `TOKEN_AMOUNT` and calls
   `PalmLauncher.launch()`, which atomically wraps ETH, creates the pair if it doesn't exist, adds
   liquidity, and sends LP tokens to `RECIPIENT` — all inside the Uniswap Router's own
   `addLiquidityETH` call.

   Note: because `Token.sol` is intentionally kept to a plain ERC20 with no `permit()` (EIP-2612),
   the approval and the launch are two separate on-chain calls, both broadcast automatically by
   the `Launch.s.sol` script in one run. If you want the launch step to be a single raw
   transaction from a wallet's perspective, you would need to add EIP-2612 permit support to the
   token — left out here by design, per the "keep the token minimal" requirement.

## Setup

```bash
forge init --no-git --force .   # if you haven't already initialized this as a Foundry project
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install foundry-rs/forge-std --no-commit
cp .env.example .env
# fill in .env with your values
source .env
```

## Usage

### 1. Deploy the launcher (once per chain)

```bash
forge script script/DeployLauncher.s.sol:DeployLauncher \
  --rpc-url $RPC_URL \
  --broadcast
```

Copy the printed `Launcher Address` into `LAUNCHER_ADDRESS` in your `.env`.

### 2. Transaction 1 — deploy your token

```bash
forge script script/DeployToken.s.sol:DeployToken \
  --rpc-url $RPC_URL \
  --broadcast
```

Copy the printed `Token Address` into `TOKEN_ADDRESS` in your `.env`.

### 3. Transaction 2 — launch it

```bash
forge script script/Launch.s.sol:Launch \
  --rpc-url $RPC_URL \
  --broadcast
```

This prints the token, pair, router, factory, recipient, LP balance, ETH used, and tokens used.
Gas used and the transaction hash for every broadcast call are printed by `forge` itself in the
script's console summary, and are also saved to
`broadcast/Launch.s.sol/<chainId>/run-latest.json`.

## Testing

The test suite runs against a real Uniswap V2 deployment via a mainnet fork (no mocks — this
exercises the actual Router/Factory/WETH contracts):

```bash
forge test --match-contract PalmLauncherTest --fork-url $MAINNET_RPC_URL -vvv
```

## Security notes

- `PalmLauncher` is stateless between calls and holds no admin rights over any pair or token — it
  only ever custodies tokens/ETH for the duration of a single `launch()` call.
- `launch()` is `nonReentrant` and uses OpenZeppelin's `SafeERC20` for all token transfers/approvals.
- `amountTokenMin` / `amountETHMin` are passed as `0` to the router. This is safe for a token's
  **first-ever** liquidity add (there is no existing price to be sandwiched against), but if you
  call `launch()` again against a token that already has liquidity, you are exposed to
  front-running/sandwich risk like any zero-slippage-protection liquidity add. Only use this
  function for a token's initial launch.
- The token's owner can only rescue *foreign* ERC20 tokens sent to the token contract by mistake —
  never the token's own balance, and never anything held by the launcher (the launcher never
  retains a balance after a call completes).
- All addresses (router, factory, WETH) are validated against the launcher's own configuration in
  `Launch.s.sol` before broadcasting, so a misconfigured `.env` fails fast instead of silently
  sending funds to the wrong place.
- This project intentionally does **not** implement Uniswap V3/V4 support, generic launcher
  factories, or any anti-bot/tax/fee mechanics — scope is deliberately limited to a clean,
  auditable Uniswap V2 launch flow.

## Chain compatibility

Works on any EVM chain with a standard Uniswap V2 Router02 + Factory + WETH deployment (or a
byte-for-byte compatible fork), including Robinhood Chain. Just set `ROUTER`, `FACTORY`, and
`WETH` in `.env` to the correct addresses for your target chain.
