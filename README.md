# Onyx (by Enzyme Protocol)

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

Onyx (by Enzyme Protocol) is a set of EVM-compatible smart contracts to tokenize on- and off-chain value.

For more information, see the Onyx General Spec [link forthcoming]

## Security Issues and Bug Bounty

If you find a vulnerability that may affect live deployments, you can submit a report via:

A. Immunefi (https://immunefi.com/bounty/enzymefinance/), or

B. Direct email to [security@enzyme.finance](mailto:security@enzyme.finance)

Please **DO NOT** open a public issue.

## Using this Repository

### Prerequisites

- [foundry](https://github.com/foundry-rs/foundry)

### Compile Contracts

```
forge build
```

### Run all tests

```
forge test
```

### Utility Scripts

Utility scripts can be found in the `scripts/` folder.

## Deploying contracts

```
make deploy NETWORK=<spec> CONTRACT=<Name>
```

- `<spec>`: single network (`arbitrum`), comma-separated subset (`arbitrum,base`), or `all` (deploys to all networks).
- Supported networks: `mainnet, arbitrum, base, ethereum_sepolia, mega_eth, plume`.
- Optional constructor args: write `deploy/<CONTRACT>/.args.<network>.txt` before deploying (e.g., `deploy/SharesDeployer/.args.ethereum_sepolia.txt`). Omit the file if the contract has no constructor args.
- Defaults: keystore `<network>-deployer` (override via `ACCOUNT=...`); verifier resolved per network (Etherscan v2 via `foundry.toml [etherscan]`, Blockscout for `mega_eth` and `plume`).
- Successful deploys append to `deploy/logs/log.<network>.txt`.
- Multi-network deploys prompt for each keystore password sequentially upfront (deduped by account), then run `forge create` concurrently. Per-chain log lines are prefixed with `[<network>]` in a distinct color; set `NO_COLOR=1` to disable (also auto-disabled when stdout isn't a TTY).
- See `make help` for full options.

## Licensing

- Source-available under Business Source License 1.1 (BUSL-1.1).
- See [LICENSES/BUSL-1.1](LICENSES/BUSL-1.1) for terms and change date.

SPDX identifiers:

- All first-party files: `BUSL-1.1`
- Vendored third-party files retain original identifiers (e.g., `MIT`).
