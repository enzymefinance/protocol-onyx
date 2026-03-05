---
Title:    Extensive QA
Author:   ChainSecurity
Date:     03. Mar, 2026
Client:   Enzyme Foundation
---

# Extensive QA


This document reflects an extensive, time-limited QA focused on identifying potential high-impact security vulnerabilities in the code within scope. This QA is not a comprehensive security audit nor does it target finding all vulnerabilities. Instead, it provides a best-effort assessment of whether the code meets core security properties that protect the system's funds, and highlights areas that may require deeper analysis like a full audit or other security measures.


## SyncDepositHandler - Synchronous Deposit Flow

### Scope

Repository: https://github.com/enzymefinance/protocol-onyx

`git diff 1130584..82b7370`:

```
src/components/issuance/deposit-handlers/SyncDepositHandler.sol  [NEW]
```

### Overview

`SyncDepositHandler` allows depositors to exchange an ERC20 asset for pro-rated vault shares within a single transaction.

A deposit is accepted when the asset amount is non-zero, the depositor is on an optional allowlist, the cached share price from `ValuationHandler` is within a configurable staleness threshold, and the deposit asset has a valid, non-expired rate in `ValuationHandler`.

Shares are determined by converting the asset amount to a canonical value via `convertAssetAmountToValue`, which is then converted to gross shares based on the current share price, minus an entrance fee if a fee handler is set.

### Trust Model

* **Admin / Owner**: Trusted to configure `maxSharePriceStaleness`, `depositorAllowlist`, asset rates in `ValuationHandler`, the fee handler, and to register this contract as a deposit handler on `Shares`. Misconfiguration by admin can lead to incorrect share pricing or blocked deposits.
* **Other components** (`ValuationHandler`, `FeeHandler`, `DepositorAllowlist`): Admin-configured and trusted to return correct share prices, asset-to-value conversions, fee amounts, and allowlist membership. The share price is a cached storage value, not recalculated on-the-fly. Asset conversion depends on admin-set exchange rates with expiry timestamps. A fee exceeding gross shares would cause an arithmetic underflow revert, blocking deposits.
* **Deposit asset**: Assumed to be a standard ERC20 without fee-on-transfer, rebasing, or ERC-777 callback behavior.

### Risk

* **Stale pricing.** Price data could be stale, leading to depositors receiving more or fewer shares than warranted.
  * *QA Confidence*: High. The damage due to immediate minting of shares is limited by `maxSharePriceStaleness` and, thus, the impact of potentially stale price feeds is capped.
  * *System Risk*: Low, provided `maxSharePriceStaleness` is configured to a reasonable threshold and share price updates happen frequently. The tighter the staleness bound, the smaller the arbitrage window.

* **Incorrect share calculation.** Logic bugs or incorrect pricing and calculations could cause the minted share amount to diverge from the deposited value, leaving depositors over- or under-compensated.
  * *QA Confidence*: High. The share amount is derived from the deposit value and the current share price, with the entrance fee applied as expected. The calculation follows the same approach as `ERC7540LikeDepositQueue`.
  * *System Risk*: High. An incorrect calculation directly impacts every deposit, over- or under-minting shares and distorting the value held by all existing shareholders.

* **Deposit DoS.** DoS of the contract could be caused in various ways.
  * *QA Confidence*: High. Reconfiguration is easily executed.
  * *System Risk*: Low. Deposits are blocked but no funds are at risk. The DoS is recoverable via admin reconfiguration.

* **Broken Access Control.** A bug in access control could lead to malicious configurations allowing for violation of the deposit constraints and thus also to potential share price arbitrage. Note that this applies to both the admin-controlled functions and the deposit function (i.e. broken depositor/staleness validation).
  * *QA Confidence*: High. Access control for the admin functions is simple. For deposits, both `__validateDepositor` and `__validateSharePriceTimestamp` are applied on all deposit paths.
  * *System Risk*: Medium. A bypass of access control would allow unauthorized minting or mispriced deposits, directly impacting existing shareholders.

* **Incorrect fund movement.** A bug in the deposit flow could result in shares being minted without the asset transfer occurring, or the asset being transferred without shares being minted. Either case would break the accounting between shareholders and underlying assets.
  * *QA Confidence*: High. Both `mintFor` and `safeTransferFrom` are called unconditionally in `__deposit`. The mint-before-transfer ordering deviates from checks-effects-interactions but both calls execute within the same atomic transaction.
  * *System Risk*: High. Minting without transfer dilutes existing shareholders. Transfer without minting causes direct loss for the depositor.

### Findings

* **Informational** : After `init`, the default state has no depositor allowlist (`address(0)`) and `maxSharePriceStaleness` of `0`. While the staleness default effectively blocks deposits (requires same-block price update), if the admin sets `maxSharePriceStaleness` before configuring an allowlist, anyone can deposit. Since the `init` function only accepts the asset address, allowlist and staleness must be configured in separate transactions, creating a window where deposit constraints may not yet be fully in place.

---

# Limitations and Use of This Report
This report was created at the client's request and is provided "as-is." The ChainSecurity Terms of Business apply. All rights reserved. (c) by ChainSecurity.

This QA was performed within a limited scope and timeframe, and cannot guarantee finding all vulnerabilities. We draw attention to the fact that, due to inherent limitations in any software development process, an inherent risk remains that even major failures can remain undetected. The report reflects our assessment of the code at a specific point in time and does not account for subsequent changes to the code, environment, or third-party dependencies. Use of the report and implementation of any recommendations is at the client's discretion and risk.
