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

## Licensing

- Source-available under Business Source License 1.1 (BUSL-1.1).
- See [LICENSES/BUSL-1.1](LICENSES/BUSL-1.1) for terms and change date.

SPDX identifiers:

- All first-party files: `BUSL-1.1`
- Vendored third-party files retain original identifiers (e.g., `MIT`).
