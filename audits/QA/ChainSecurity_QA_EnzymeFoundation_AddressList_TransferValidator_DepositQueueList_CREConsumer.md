---
Title:    Extensive QA
Author:   ChainSecurity  
Date:     10. Feb, 2026
Client:   Enzyme Foundation
---

# Extensive QA


This document reflects an extensive, time-limited QA focused on identifying potential high-impact security vulnerabilities in the code within scope. This QA is not a comprehensive security audit nor does it target finding all vulnerabilities. Instead, it provides a best-effort assessment of whether the code meets core security properties that protect the system's funds, and highlights areas that may require deeper analysis like a full audit or other security measures.


## Address List Infrastructure

### Scope

Repository: https://github.com/enzymefinance/protocol-onyx-dev (to be published at https://github.com/enzymefinance/protocol-onyx)

`git diff b20a157..449ae5c`:

```
src/infra/lists/address-list/AddressListBase.sol       [NEW]
src/infra/lists/address-list/IAddressList.sol           [NEW]
src/infra/lists/address-list/OwnableAddressList.sol     [NEW]
src/components/lists/SharesOwnedAddressList.sol         [NEW]
src/components/fees/performance-fee-trackers/ContinuousFlatRatePerformanceFeeTracker.sol  (lint suppression only)
```

### Overview

This diff introduces a reusable address list system. An `IAddressList` interface defines the `isInList` check, and `AddressListBase` provides the core logic: a boolean mapping with add/remove operations and a virtual `isAuth` hook for access control, all backed by ERC-7201 namespaced storage.

Two concrete implementations build on this base:

* `OwnableAddressList` uses OpenZeppelin's `OwnableUpgradeable` with the standard `initializer` modifier, designed for beacon proxy deployment, and delegates authorization to `owner()`.
* `SharesOwnedAddressList` is scoped to the Shares component and routes authorization through `ComponentHelpersMixin.__isAdminOrOwner`, which calls `Shares.isAdminOrOwner`.

A lint suppression was also added to `ContinuousFlatRatePerformanceFeeTracker` (no logic changes).

### Trust Model

* `owner()` is trusted for `OwnableAddressList`.
* Admin/owner via `Shares.isAdminOrOwner` is trusted for `SharesOwnedAddressList`.

### Risk

* **Broken access control on list management.** Unauthorized actors could add or remove list members, undermining any access policy built on the list.
  * *QA Confidence*: High. The `onlyAuth` modifier delegates to `owner()` or `isAdminOrOwner` depending on the subclass, both paths are straightforward. `addToList`/`removeFromList` are protected, duplicates and missing entries revert, re-initialization is blocked by OpenZeppelin's `initializer`, and events are emitted for every mutation.
  * *System Risk*: Low. The authorization model is simple and testing is straightforward; actual impact depends on what the list controls downstream.

* **Incorrect logic in list management.** A bug in `addToList`, `removeFromList`, or `isInList` could silently corrupt list state or return incorrect membership results, breaking any downstream policy that depends on the list.
  * *QA Confidence*: High. All three functions are simple with no arithmetic or multi-step state transitions. Checks are thorough: `addToList` guards against duplicates, `removeFromList` guards against removing absent entries, and events are emitted for every mutation.
  * *System Risk*: Low. The logic is minimal and directly auditable.


### Findings

* **Note** : there is no way to enumerate list members on-chain. Membership is stored as a `mapping(address => bool)`, so consumers need to index `ItemAdded`/`ItemRemoved` events off-chain.

---

## Shares Transfer Validator

### Scope

Repository: https://github.com/enzymefinance/protocol-onyx-dev (to be published at https://github.com/enzymefinance/protocol-onyx)

`git diff 449ae5c..e68728c`:

```
src/components/shares-transfer-validators/AddressListsSharesTransferValidator.sol  [NEW]
```

### Overview

Adds `AddressListsSharesTransferValidator`, an implementation of `ISharesTransferValidator`. It validates both sender and recipient of each shares transfer against configurable `IAddressList` references. Each side operates independently in one of three modes: `None` (unrestricted), `Allow` (must be on the list), or `Disallow` (must not be on the list). Configuration is via `setRecipientList`/`setSenderList`, both gated by `onlyAdminOrOwner`.

### Trust Model

* Admin/owner is trusted for list configuration (`setRecipientList`/`setSenderList`).
* External `IAddressList` contracts are trusted to be configured and behave correctly.

### Risk

* **Validation logic error in transfer gating.** A bug in the allow/disallow branching, in `setRecipientList`/`setSenderList`, or a misconfigured list/type pairing could block legitimate share transfers, permit unauthorized ones, or cause unexpected reverts.
  * *QA Confidence*: High. Each mode is handled in a separate `if` branch with simple boolean checks, all three modes covered with a defensive `return false` fallback. `__validateSetList` enforces consistency between list address and type. Each setter is a single-assignment operation followed by an event, both gated by `onlyAdminOrOwner`. The referenced list must be correctly set up before activating the respective list type.
  * *System Risk*: Low. Straightforward logic reduces the likelihood of error. Configuration is expected to be correct per the trust model, and admin can correct any misconfiguration.

### Findings

* **Informational** : the `require` in `__validateSetList` mixes `&&` and `||` without explicit parentheses. Solidity operator precedence gives the correct result, but parentheses would make the intent clearer.
* **Note** : transfer initiator (operator) is never validated. `ISharesTransferValidator` only takes `_from`, `_to`, and `_amount`; there is no parameter for `msg.sender`. When `Shares.transferFrom` is called by an approved spender, that spender cannot be checked against any list. This is consistent with ERC-20 semantics where the principal parties are `from` and `to`, but it means the allowlist/blocklist cannot gate who initiates transfers.
* **Note** : `Shares.authTransfer` and `Shares.authTransferFrom` bypass the validator entirely by calling the parent ERC-20 transfer directly. Admin and system-initiated transfers are not subject to the allowlist/blocklist. This is by design but means the transfer validator only gates user-facing `transfer`/`transferFrom` calls.

---

## Deposit Queue External Depositor Address List

### Scope

Repository: https://github.com/enzymefinance/protocol-onyx-dev (to be published at https://github.com/enzymefinance/protocol-onyx)

`git diff e68728c..54edc01`:

```
src/components/issuance/deposit-handlers/ERC7540LikeDepositQueue.sol  [MODIFY]
```

### Overview

Extends `ERC7540LikeDepositQueue` with a new deposit gate: alongside the existing internal mapping-based allowlist (`ControllerAllowlistInternal`), deposits can now be restricted via an external `IAddressList` contract (`ControllerAllowlistExternal`). The admin selects the active mode through `setDepositRestriction`, and the check runs inside a new `__validateDepositRequest` helper.

### Trust Model

* Admin/owner is trusted for deposit restriction and allowlist configuration.
* External `IAddressList` contract is trusted to be configured and behave correctly.

### Risk

* **Validation error in deposit gating.** A bug in `__validateDepositRequest` (or in the configuration logic) could DoS deposits or permit unauthorized ones, whether through incorrect branching logic, an enum ordinal shift after upgrade silently switching restriction modes, or an unconfigured external allowlist causing unexpected reverts.
  * *QA Confidence*: High. All three enum cases handled in distinct branches and setters are straightforward. Enum ordinals and fail-closed behavior were considered, additionally.
  * *System Risk*: Low. Backwards-compatible enum layout, fail-closed behavior for unconfigured lists, and admin can correct misconfiguration, limiting the damage window.

### Findings

* **Informational** : no cross-validation between the restriction type and the external list address. Calling `setDepositRestriction(ControllerAllowlistExternal)` without first setting `controllerAllowlist` will revert all deposits until the list is configured. Operators need to be aware of the correct sequencing.
* **Note** : `__validateDepositRequest` lacks a final `else { revert }` for unrecognized enum values. Currently unreachable, but if the enum is extended without updating the function, a new value would silently pass through.
* **Note** : switching away from `ControllerAllowlistExternal` does not clear the stored `controllerAllowlist` reference. The old address remains in storage even though it is no longer read. Functionally harmless, but the stale value could be confusing when inspecting storage.

---

## CRE Workflow Consumer

### Scope

Repository: https://github.com/enzymefinance/protocol-onyx-dev (to be published at https://github.com/enzymefinance/protocol-onyx)

`git diff 54edc01..1130584`:

```
src/components/automations/chainlink-cre/CreWorkflowConsumer.sol     [NEW]
src/components/automations/chainlink-cre/IReceiver.sol               [NEW]
src/components/value/position-trackers/LinearCreditDebtTracker.sol   [MODIFY, comments only]
```

### Overview

`CreWorkflowConsumer` is a consumer contract for Chainlink's Compute Runtime Environment (CRE). An off-chain CRE workflow produces a signed report, the Chainlink-managed `KeystoneForwarder` validates it (DON signature verification, replay protection), and then calls `onReport` on this consumer.

`onReport` performs layered validation: it first checks that the caller is the immutable `CHAINLINK_KEYSTONE_FORWARDER`, then decodes the metadata and verifies the `workflowId`, `workflowName` (bytes10), and `workflowOwner` against stored or immutable values. If all checks pass, the report payload is decoded as an array of `OpenAccessLimitedCallForwarder.Call` structs and forwarded to a `LimitedAccessLimitedCallForwarder` for execution.

The forwarder is the final security boundary. It enforces both a whitelist of `(target, selector)` pairs and a set of authorized callers, so even if the workflow layer is compromised, the impact is bounded by whatever functions the admin whitelisted. The workflow owner is immutable (set at construction); the workflow name and forwarder reference are set during `init()`.

`LinearCreditDebtTracker.calcItemValue` comments were expanded (no logic changes).

### Trust Model

* Chainlink `KeystoneForwarder` and DON are trusted to correctly verify signatures and prevent replays and to validate the metadata accordingly.
* Admin/owner is trusted for forwarder whitelist configuration and workflow ID management.
* Whitelisted `(target, selector)` pairs on the `LimitedAccessLimitedCallForwarder` are assumed appropriate for the use case.

### Risk

* **Failure and corner cases in CRE.** Unexpected or not directly evident edge cases, e.g., a compromised DON or malicious `KeystoneForwarder`, could craft valid-looking reports and execute arbitrary whitelisted calls, potentially manipulating on-chain state.
  * *QA Confidence*: Medium. Chainlink infrastructure is trusted per the trust model, but was insufficiently covered in the QA. Execution is delegated to `LimitedAccessLimitedCallForwarder.executeCalls` and `CreWorkflowConsumer` must be registered as a `user` on the forwarder, but the forwarder whitelist contents are not in scope. Actual impact depends on how permissive the whitelist is.
  * *System Risk*: Medium. Attacker can execute any whitelisted `(target, selector)` call with arbitrary calldata; severity is bounded by the forwarder whitelist.

* **Re-entrancy into `onReport` during system execution.** If a system action makes an external call that triggers report delivery via the `KeystoneForwarder`, the forwarded calls re-enter the system mid-execution, potentially corrupting state.
  * *QA Confidence*: Low. Not validated due to scope limitations.
  * *System Risk*: Medium. Could lead to unexpected behavior if affected functions lack re-entrancy protections.

* **Logic error in the contract's validation logic.** A flaw in the metadata validation or a generally flawed access control scheme could allow an attacker to bypass checks and trigger unauthorized call execution.
  * *QA Confidence*: High. Compared against the Chainlink [`ReceiverTemplate`](https://docs.chain.link/cre/guides/workflow/using-evm-client/onchain-write/building-consumer-contracts): `CreWorkflowConsumer` is stricter (immutable forwarder address, unconditional validation of workflow ID, name, and owner). Name collision resistance handled by always checking the owner alongside the name (80-bit truncation makes collisions feasible if checked alone). Metadata layout matches `abi.encodePacked` per the template; length is considered accordingly and also validated by the `KeystoneForwarder`. `supportsInterface` covers `IReceiver` and `IERC165`.
  * *System Risk*: Low. Metadata validation is comprehensive and stricter than the reference template.

### Findings

* **Informational** : `init()` has no access control and double-init is prevented by a custom `__isInitialized` check. This is expected since the contract is deployed atomically via factory. Uses ERC-7201 namespaced storage with constructor-time slot verification.
* **Note** : if any forwarded call reverts, the entire `onReport` transaction reverts. The Chainlink `KeystoneForwarder` can retry delivery.
* **Note** : re-entrancy into `onReport` is possible if an Enzyme system action makes an external call that triggers report delivery via the `KeystoneForwarder`, re-entering the system mid-execution. Not validated due to scope limitations.
* **Note** : the `canCall` whitelist only validates `(target, selector)` pairs. Depending on the use case, more restrictive validation of call parameters beyond the selector may be necessary.
* **Note** : `init()` does not verify that the `CreWorkflowConsumer` is registered as a user on the `LimitedAccessLimitedCallForwarder`. If the forwarder's user list is not configured before the first report, all `onReport` calls will revert. This is a deployment sequencing requirement.



# Limitations and Use of This Report
This report was created at the client's request and is provided "as-is." The ChainSecurity Terms of Business apply. All rights reserved. (c) by ChainSecurity.

This QA was performed within a limited scope and timeframe, and cannot guarantee finding all vulnerabilities. We draw attention to the fact that, due to inherent limitations in any software development process, an inherent risk remains that even major failures can remain undetected. The report reflects our assessment of the code at a specific point in time and does not account for subsequent changes to the code, environment, or third-party dependencies. Use of the report and implementation of any recommendations is at the client's discretion and risk.