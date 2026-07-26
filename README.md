# Waterfall

Waterfall is a simple USDC treasury contract built for Arc's "Programmable Money Hackathon" Hackathon.

USDC sent to the treasury is distributed through a list of ordered rules.
Earlier rules have priority. If the balance is not enough, later rules receive
less or nothing.

## Current status

The first version of the smart contract is complete.

- Percentage payments
- Fixed payments
- Target balance top-ups
- Remainder payments
- Up to 6 ordered rules
- Owner-managed rule configuration
- Permissionless execution
- Pause, unpause and emergency withdrawal
- Distribution preview

The frontend and Arc Testnet deployment have not been added yet.

## Planned Circle integration

We plan to add a **Fund from another chain** option with
[Circle App Kit](https://docs.arc.io/app-kit).

The first version will use App Kit Bridge with a browser wallet:

1. Bridge USDC from a supported testnet, such as Ethereum Sepolia, to Arc Testnet.
2. Transfer the received USDC to the Waterfall treasury.
3. Preview and execute the existing distribution rules.

This will be added after the core Arc funding and distribution flow is working.
It is not implemented yet.

## Example distribution

For a treasury balance of 100 USDC:

| Rule | Amount |
| --- | ---: |
| Taxes | 20 USDC |
| Supplier | 30 USDC |
| Reserve | 25 USDC |
| Profit | 25 USDC |

If the reserve address already holds 25 USDC, it receives nothing during the
second distribution and the profit address receives 50 USDC.

## Tests

The test suite covers rule validation, permissions, pause controls, insufficient
balances, distribution previews and the main demo scenarios.

Current result:

```text
26 tests passed
0 tests failed
```

## Setup

Foundry is required.

```bash
cd contracts
forge install OpenZeppelin/openzeppelin-contracts@v5.4.0 --no-commit
forge install foundry-rs/forge-std@v1.9.7 --no-commit
forge build
forge test
```

## Project structure

```text
contracts/
|-- src/WaterfallTreasury.sol
|-- test/WaterfallTreasury.t.sol
|-- test/mocks/MockUSDC.sol
|-- foundry.toml
`-- remappings.txt
```

`MockUSDC` is only used for local tests. The official USDC contract will be used
on Arc Testnet.

Hackathon prototype. Not audited. Testnet use only.
