# Protocol OnyX Graph

The Protocol Onxy Graph is a visual companion to the [Protocol Onyx Repo](). It's designed to be used alongside the repository's end to end tests to visualize their call flows.

<div id="graph" class="graph-container"></div>

<style>
    /* Main container for the graph and its controls */
    .graph-container {
        position: relative;
        text-align: center;
        background-color: #1a1a1a;
        border-radius: 8px;
        height: 650px;
        width: 95%;
        max-width: 1400px;
        margin: 0 auto;
        overflow: auto;
        resize: vertical;
    }

    /* Rule for when the container is in fullscreen */
    .graph-container.fullscreen {
        position: fixed;
        top: 0;
        left: 0;
        width: 100vw;
        height: 100vh;
        max-width: none; /* Override max-width in fullscreen */
        border-radius: 0;
        z-index: 2000; /* Ensure it's on top of everything */
    }

    /* --- UI CONTROLS --- */
    .graph-controls {
        position: sticky;
        top: 0;
        left: 0;
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 10px;
        z-index: 1001;
        background: rgba(40, 40, 40, 0.9);
        padding: 8px 15px;
        width: 100%;
        box-sizing: border-box;
        backdrop-filter: blur(5px);
    }
    .graph-controls input,
    .graph-controls button,
    .graph-controls select,
    .graph-controls label {
        padding: 8px 12px;
        border: none;
        font-size: 14px;
        background-color: #333;
        color: white;
        border: 1px solid #555;
    }
    .graph-controls button {
        cursor: pointer;
        transition: background-color: 0.2s;
    }
    .graph-controls select {
        border-radius: 4px;
    }

    .fullscreen-button {
        margin-left: auto; /* Pushes the button to the far right */
        background-color: #333;
        color: white;
        border: 1px solid #555;
        padding: 8px 12px;
        cursor: pointer;
        border-radius: 4px;
    }
    .fullscreen-button:hover {
        background-color: #007bff;
    }

    /* Mode Selector (Segmented Control) */
    .mode-selector {
        display: flex;
        border-radius: 4px;
        overflow: hidden;
    }
    .mode-selector button {
        border-radius: 0;
        border-right: 1px solid #555;
    }
    .mode-selector button:last-child {
        border-right: none;
    }
    .mode-selector button.active, .mode-selector button:hover {
        background-color: #007bff;
        color: white;
    }

    .playback-controls {
        display: none; /* Hidden by default */
        gap: 10px;
        align-items: center;
    }
    .graph-container.animation-mode-on .playback-controls {
        display: flex;
    }

    /* --- HIGHLIGHT & ANIMATION STYLES --- */
    .graph-container svg g.dimmed {
        opacity: 0.15;
    }
    .graph-container svg g.highlight {
        opacity: 1 !important;
        transition: opacity 0.3s;
    }
    .graph-container svg g.node.node-start polygon {
        stroke: #00aaff;
        stroke-width: 3px;
    }
    .graph-container svg g.node.node-active polygon {
        stroke: #ffcc00;
        stroke-width: 3px;
    }

    .graph-container svg g.node polygon.search-highlight {
        stroke: #17a2b8 !important; /* A bright cyan color */
        stroke-width: 4px !important;
    }

    /* Edge styles now use a CSS variable for color */
    .graph-container svg g.edge.path-viewed path {
        stroke: var(--edge-color);
        stroke-width: 2.5px;
        opacity: 0.8;
    }
    .graph-container svg g.edge.highlight-path path {
        stroke: var(--edge-color);
        stroke-width: 3px;
        stroke-dasharray: 8;
        animation: dash 1.5s linear infinite;
    }
    @keyframes dash { to { stroke-dashoffset: -100; } }
</style>

<script src="//d3js.org/d3.v7.min.js"></script>
<script src="https://unpkg.com/@hpcc-js/wasm@2.20.0/dist/graphviz.umd.js"></script>
<script src="https://unpkg.com/d3-graphviz@5.6.0/build/d3-graphviz.js"></script>

<script>
document.addEventListener("DOMContentLoaded", function() {
    function setupGraph(containerId, dotUrl) {
        const graphContainerElement = document.getElementById(containerId);
        const container = d3.select(`#${containerId}`);
        if (container.empty()) return;

        let currentMode = 'animation';
        let animationSpeed = 1000;
        let animationState = {
            isPlaying: false, isPaused: false, currentStep: 0,
            sequence: [], flowName: null, startNode: null,
        };
        let graph;

        container.classed("animation-mode-on", currentMode === 'animation');

        const animationTriggers = {
          // 1. SLOC 555
          "SharesBeaconFactory":[
            { name: "🔎 implementation", flow: "", startNode: "SharesBeaconFactory.implementation"},
            { name: "🔎 isInstance", flow: "", startNode: "SharesBeaconFactory.isInstance"},
            { name: "🔎 GLOBAL", flow: "", startNode: "SharesBeaconFactory.GLOBAL"},
            { name: "▶️ constructor", flow: "SharesBeaconFactory_constructor", startNode: "SharesBeaconFactory.constructor"},
            { name: "▶️ deployProxy", flow: "SharesBeaconFactory_deployProxy", startNode: "SharesBeaconFactory.deployProxy"},
            { name: "▶️ setImplementation", flow: "SharesBeaconFactory_setImplementation", startNode: "SharesBeaconFactory.setImplementation"},
          ],
          // 2. SLOC  681
          "Shares": [
            { name: "🔎 name", flow: "", startNode: "Shares.name"},
            { name: "🔎 symbol", flow: "", startNode: "Shares.symbol"},
            { name: "🔎 decimals", flow: "", startNode: "Shares.decimals"},
            { name: "🔎 totalSupply", flow: "", startNode: "Shares.totalSupply"},
            { name: "🔎 balanceOf", flow: "", startNode: "Shares.balanceOf"},
            { name: "🔎 allowance", flow: "", startNode: "Shares.allowance"},
            { name: "🔎 pendingOwner", flow: "", startNode: "Shares.pendingOwner"},
            { name: "🔎 owner", flow: "", startNode: "Shares.owner"},
            { name: "🔎 getValueAsset", flow: "", startNode: "Shares.getValueAsset"},
            { name: "🔎 getFeeHandler", flow: "", startNode: "Shares.getFeeHandler"},
            { name: "🔎 getSharesTransferValidator", flow: "", startNode: "Shares.getSharesTransferValidator"},
            { name: "🔎 getValuationHandler", flow: "", startNode: "Shares.getValuationHandler"},
            { name: "🔎 isDepositHandler", flow: "", startNode: "Shares.isDepositHandler"},
            { name: "🔎 isRedeemHandler", flow: "", startNode: "Shares.isRedeemHandler"},
            { name: "🔎 isAdmin", flow: "", startNode: "Shares.isAdmin"},
            { name: "🔎 isAdminOrOwner", flow: "", startNode: "Shares.isAdminOrOwner"},
            { name: "▶️ transferOwnership", flow: "", startNode: "Shares.transferOwnership"},
            { name: "▶️ acceptOwnership", flow: "", startNode: "Shares.acceptOwnership"},
            { name: "▶️ renounceOwnership", flow: "", startNode: "Shares.renounceOwnership"},
            { name: "▶️ transfer", flow: "", startNode: "Shares.transfer"},
            { name: "▶️ transferFrom", flow: "", startNode: "Shares.transferFrom"},
            { name: "▶️ approve", flow: "", startNode: "Shares.approve"},
            { name: "▶️ constructor", flow: "", startNode: "Shares.constructor"},
            { name: "▶️ init", flow: "Shares_init", startNode: "Shares.init"},
            { name: "▶️ addAdmin", flow: "Shares_addAdmin", startNode: "Shares.addAdmin"},
            { name: "▶️ removeAdmin", flow: "Shares_removeAdmin", startNode: "Shares.removeAdmin"},
            { name: "▶️ authTransfer", flow: "", startNode: "Shares.authTransfer"},
            { name: "▶️ authTransferFrom", flow: "", startNode: "Shares.authTransferFrom"},
            { name: "▶️ addDepositHandler", flow: "Shares_addDepositHandler", startNode: "Shares.addDepositHandler"},
            { name: "▶️ addRedeemHandler", flow: "Shares_addRedeemHandler", startNode: "Shares.addRedeemHandler"},
            { name: "▶️ removeDepositHandler", flow: "Shares_removeDepositHandler", startNode: "Shares.removeDepositHandler"},
            { name: "▶️ removeRedeemHandler", flow: "Shares_removeRedeemHandler", startNode: "Shares.removeRedeemHandler"},
            { name: "▶️ setFeeHandler", flow: "Shares_setFeeHandler", startNode: "Shares.setFeeHandler"},
            { name: "▶️ setSharesTransferValidator", flow: "Shares_setSharesTransferValidator", startNode: "Shares.setSharesTransferValidator"},
            { name: "▶️ setValuationHandler", flow: "Shares_setValuationHandler", startNode: "Shares.setValuationHandler"},
            { name: "▶️ sharePrice", flow: "Shares_sharePrice", startNode: "Shares.sharePrice"},
            { name: "▶️ shareValue", flow: "Shares_shareValue", startNode: "Shares.shareValue"},
            { name: "▶️ burnFor", flow: "", startNode: "Shares.burnFor"},
            { name: "▶️ mintFor", flow: "", startNode: "Shares.mintFor"},
            { name: "▶️ withdrawAssetTo", flow: "", startNode: "Shares.withdrawAssetTo"},
          ],
          // 3. SLOC 569
          "ValuationHandlerBeaconFactory": [
            { name: "🔎 implementation", flow: "", startNode: "ValuationHandlerBeaconFactory.implementation"},
            { name: "🔎 GLOBAL", flow: "", startNode: "ValuationHandlerBeaconFactory.GLOBAL"},
            { name: "🔎 instanceToShares", flow: "", startNode: "ValuationHandlerBeaconFactory.instanceToShares"},
            { name: "🔎 getSharesForInstance", flow: "", startNode: "ValuationHandlerBeaconFactory.getSharesForInstance"},
            { name: "▶️ constructor", flow: "ValuationHandlerBeaconFactory_constructor", startNode: "ValuationHandlerBeaconFactory.constructor"},
            { name: "▶️ setImplementation", flow: "", startNode: "ValuationHandlerBeaconFactory.setImplementation"},
            { name: "▶️ deployProxy", flow: "", startNode: "ValuationHandlerBeaconFactory.deployProxy"},
          ],
          // 4. SlOC  1864
          "ValuationHandler": [
            { name: "🔎 SHARES", flow: "", startNode: "ValuationHandler.SHARES"},
            { name: "🔎 RATE_PRECISION", flow: "", startNode: "ValuationHandler.RATE_PRECISION"},
            { name: "🔎 VALUATION_HANDLER_STORAGE_LOCATION", flow: "", startNode: "ValuationHandler.VALUATION_HANDLER_STORAGE_LOCATION"},
            { name: "🔎 VALUATION_HANDLER_STORAGE_LOCATION_ID", flow: "", startNode: "ValuationHandler.VALUATION_HANDLER_STORAGE_LOCATION_ID"},
            { name: "🔎 getAssetRateInfo", flow: "", startNode: "ValuationHandler.getAssetRateInfo"},
            { name: "🔎 getDefaultSharePrice", flow: "", startNode: "ValuationHandler.getDefaultSharePrice"},
            { name: "🔎 getPositionTrackers", flow: "", startNode: "ValuationHandler.getPositionTrackers"},
            { name: "🔎 isPositionTracker", flow: "", startNode: "ValuationHandler.isPositionTracker"},
            { name: "▶️ constructor", flow: "", startNode: "ValuationHandler.constructor"},
            { name: "▶️ convertAssetAmountToValue", flow: "", startNode: "ValuationHandler.convertAssetAmountToValue"},
            { name: "▶️ convertValueToAssetAmount", flow: "", startNode: "ValuationHandler.convertValueToAssetAmount"},
            { name: "▶️ getSharePrice", flow: "", startNode: "ValuationHandler.getSharePrice"},
            { name: "▶️ getShareValue", flow: "", startNode: "ValuationHandler.getShareValue"},
            { name: "▶️ addPositionTracker", flow: "ValuationHandler_addPositionTracker", startNode: "ValuationHandler.addPositionTracker"},
            { name: "▶️ removePositionTracker", flow: "", startNode: "ValuationHandler.removePositionTracker"},
            { name: "▶️ setAssetRate", flow: "", startNode: "ValuationHandler.setAssetRate"},
            { name: "▶️ setAssetRatesThenUpdateShareValue", flow: "", startNode: "ValuationHandler.setAssetRatesThenUpdateShareValue"},
            { name: "▶️ updateShareValue", flow: "", startNode: "ValuationHandler.updateShareValue"},
          ],
          // 5
          "FeeHandlerBeaconFactory": [
            { name: "🔎 implementation", flow: "", startNode: "FeeHandlerBeaconFactory.implementation"},
            { name: "🔎 GLOBAL", flow: "", startNode: "FeeHandlerBeaconFactory.GLOBAL"},
            { name: "🔎 instanceToShares", flow: "", startNode: "FeeHandlerBeaconFactory.instanceToShares"},
            { name: "🔎 getSharesForInstance", flow: "", startNode: "FeeHandlerBeaconFactory.getSharesForInstance"},
            { name: "▶️ constructor", flow: "FeeHandlerBeaconFactory_constructor", startNode: "FeeHandlerBeaconFactory.constructor"},
            { name: "▶️ setImplementation", flow: "", startNode: "FeeHandlerBeaconFactory.setImplementation"},
            { name: "▶️ deployProxy", flow: "", startNode: "FeeHandlerBeaconFactory.deployProxy"},
          ],
          // 6. SLOC  2084
          "FeeHandler": [
            { name: "🔎 SHARES", flow: "", startNode: "FeeHandler.SHARES"},
            { name: "▶️ constructor", flow: "", startNode: "FeeHandler.constructor"},
            { name: "getEntranceFeeBps", flow: "", startNode: "FeeHandler.getEntranceFeeBps"},
            { name: "getEntranceFeeRecipient", flow: "", startNode: "FeeHandler.getEntranceFeeRecipient"},
            { name: "getExitFeeBps", flow: "", startNode: "FeeHandler.getExitFeeBps"},
            { name: "getExitFeeRecipient", flow: "", startNode: "FeeHandler.getExitFeeRecipient"},
            { name: "getFeeAsset", flow: "", startNode: "FeeHandler.getFeeAsset"},
            { name: "getManagementFeeRecipient", flow: "", startNode: "FeeHandler.getManagementFeeRecipient"},
            { name: "getManagementFeeTracker", flow: "", startNode: "FeeHandler.getManagementFeeTracker"},
            { name: "getPerformanceFeeRecipient", flow: "", startNode: "FeeHandler.getPerformanceFeeRecipient"},
            { name: "getPerformanceFeeTracker", flow: "", startNode: "FeeHandler.getPerformanceFeeTracker"},
            { name: "getTotalValueOwed", flow: "", startNode: "FeeHandler.getTotalValueOwed"},
            { name: "getValueOwedToUser", flow: "", startNode: "FeeHandler.getValueOwedToUser"},
            { name: "claimFees", flow: "", startNode: "FeeHandler.claimFees"},
            { name: "setEntranceFee", flow: "", startNode: "FeeHandler.setEntranceFee"},
            { name: "setExitFee", flow: "", startNode: "FeeHandler.setExitFee"},
            { name: "setFeeAsset", flow: "", startNode: "FeeHandler.setFeeAsset"},
            { name: "setManagementFee", flow: "", startNode: "FeeHandler.setManagementFee"},
            { name: "setPerformanceFee", flow: "", startNode: "FeeHandler.setPerformanceFee"},
            { name: "settleDynamicFeesGivenPositionsValue", flow: "", startNode: "FeeHandler.settleDynamicFeesGivenPositionsValue"},
            { name: "settleEntranceFeeGivenGrossShares", flow: "", startNode: "FeeHandler.settleEntranceFeeGivenGrossShares"},
            { name: "settleExitFeeGivenGrossShares", flow: "", startNode: "FeeHandler.settleExitFeeGivenGrossShares"},
          ],
          // 7
          "ERC7540LikeDepositQueueBeaconFactory": [
            { name: "🔎 implementation", flow: "", startNode: "ERC7540LikeDepositQueueBeaconFactory.implementation"},
            { name: "🔎 GLOBAL", flow: "", startNode: "ERC7540LikeDepositQueueBeaconFactory.GLOBAL"},
            { name: "🔎 instanceToShares", flow: "", startNode: "ERC7540LikeDepositQueueBeaconFactory.instanceToShares"},
            { name: "🔎 getSharesForInstance", flow: "", startNode: "ERC7540LikeDepositQueueBeaconFactory.getSharesForInstance"},
            { name: "▶️ constructor", flow: "ERC7540LikeDepositQueueBeaconFactory_constructor", startNode: "ERC7540LikeDepositQueueBeaconFactory.constructor"},
            { name: "▶️ setImplementation", flow: "", startNode: "ERC7540LikeDepositQueueBeaconFactory.setImplementation"},
            { name: "▶️ ddeployProxy", flow: "", startNode: "ERC7540LikeDepositQueueBeaconFactory.deployProxy"},
          ],
          // 8. SLOC  2076
          "ERC7540LikeDepositQueue": [
            { name: "🔎 SHARES", flow: "", startNode: "ERC7540LikeDepositQueue.SHARES"},
            { name: "🔎 asset", flow: "", startNode: "ERC7540LikeDepositQueue.asset"},
            { name: "🔎 share", flow: "", startNode: "ERC7540LikeDepositQueue.share"},
            { name: "🔎 getDepositLastId", flow: "", startNode: "ERC7540LikeDepositQueue.getDepositLastId"},
            { name: "🔎 getDepositMinRequestDuration", flow: "", startNode: "ERC7540LikeDepositQueue.getDepositMinRequestDuration"},
            { name: "🔎 getDepositRequest", flow: "", startNode: "ERC7540LikeDepositQueue.getDepositRequest"},
            { name: "🔎 getDepositRestriction", flow: "", startNode: "ERC7540LikeDepositQueue.getDepositRestriction"},
            { name: "🔎 isInAllowedControllerList", flow: "", startNode: "ERC7540LikeDepositQueue.isInAllowedControllerList"},
            { name: "▶️ constructor", flow: "", startNode: "ERC7540LikeDepositQueue.constructor"},
            { name: "▶️ setAsset", flow: "", startNode: "ERC7540LikeDepositQueue.setAsset"},
            { name: "▶️ addAllowedController", flow: "", startNode: "ERC7540LikeDepositQueue.addAllowedController"},
            { name: "▶️ removeAllowedController", flow: "", startNode: "ERC7540LikeDepositQueue.removeAllowedController"},
            { name: "▶️ setDepositRestriction", flow: "", startNode: "ERC7540LikeDepositQueue.setDepositRestriction"},
            { name: "▶️ setDepositMinRequestDuration", flow: "", startNode: "ERC7540LikeDepositQueue.setDepositMinRequestDuration"},
            { name: "▶️ requestDeposit", flow: "", startNode: "ERC7540LikeDepositQueue.requestDeposit"},
            { name: "▶️ cancelDeposit", flow: "", startNode: "ERC7540LikeDepositQueue.cancelDeposit"},
            { name: "▶️ executeDepositRequests", flow: "", startNode: "ERC7540LikeDepositQueue.executeDepositRequests"},
            { name: "▶️ requestDepositReferred", flow: "", startNode: "ERC7540LikeDepositQueue.requestDepositReferred"},
          ],
          // 9.
          "ERC7540LikeRedeemQueueBeaconFactory": [
            { name: "🔎 implementation", flow: "", startNode: "ERC7540LikeRedeemQueueBeaconFactory.implementation"},
            { name: "🔎 GLOBAL", flow: "", startNode: "ERC7540LikeRedeemQueueBeaconFactory.GLOBAL"},
            { name: "🔎 instanceToShares", flow: "", startNode: "ERC7540LikeRedeemQueueBeaconFactory.instanceToShares"},
            { name: "🔎 getSharesForInstance", flow: "", startNode: "ERC7540LikeRedeemQueueBeaconFactory.getSharesForInstance"},
            { name: "▶️ constructor", flow: "ERC7540LikeRedeemQueueBeaconFactory_constructor", startNode: "ERC7540LikeRedeemQueueBeaconFactory.constructor"},
            { name: "▶️ setImplementation", flow: "", startNode: "ERC7540LikeRedeemQueueBeaconFactory.setImplementation"},
            { name: "▶️ ddeployProxy", flow: "", startNode: "ERC7540LikeRedeemQueueBeaconFactory.deployProxy"},
          ],
          // 10. SLOC  2028
          "ERC7540LikeRedeemQueue": [
            { name: "🔎 SHARES", flow: "", startNode: "ERC7540LikeRedeemQueue.SHARES"},
            { name: "🔎 asset", flow: "", startNode: "ERC7540LikeRedeemQueue.asset"},
            { name: "🔎 share", flow: "", startNode: "ERC7540LikeRedeemQueue.share"},
            { name: "🔎 getRedeemLastId", flow: "", startNode: "ERC7540LikeRedeemQueue.getRedeemLastId"},
            { name: "🔎 getRedeemMinRequestDuration", flow: "", startNode: "ERC7540LikeRedeemQueue.getRedeemMinRequestDuration"},
            { name: "🔎 getRedeemRequest", flow: "", startNode: "ERC7540LikeRedeemQueue.getRedeemRequest"},
            { name: "▶️ constructor", flow: "", startNode: "ERC7540LikeRedeemQueue.constructor"},
            { name: "▶️ setAsset", flow: "", startNode: "ERC7540LikeRedeemQueue.setAsset"},
            { name: "▶️ setRedeemMinRequestDuration", flow: "", startNode: "ERC7540LikeRedeemQueue.setRedeemMinRequestDuration"},
            { name: "▶️ cancelRedeem", flow: "", startNode: "ERC7540LikeRedeemQueue.cancelRedeem"},
            { name: "▶️ executeRedeemRequests", flow: "", startNode: "ERC7540LikeRedeemQueue.executeRedeemRequests"},
            { name: "▶️ requestRedeem", flow: "", startNode: "ERC7540LikeRedeemQueue.requestRedeem"},
          ],
          // 11
          "ContinuousFlatRateManagementFeeTrackerBeaconFactory": [
            { name: "🔎 implementation", flow: "", startNode: "ContinuousFlatRateManagementFeeTrackerBeaconFactory.implementation"},
            { name: "🔎 GLOBAL", flow: "", startNode: "ContinuousFlatRateManagementFeeTrackerBeaconFactory.GLOBAL"},
            { name: "🔎 instanceToShares", flow: "", startNode: "ContinuousFlatRateManagementFeeTrackerBeaconFactory.instanceToShares"},
            { name: "🔎 getSharesForInstance", flow: "", startNode: "ContinuousFlatRateManagementFeeTrackerBeaconFactory.getSharesForInstance"},
            { name: "▶️ constructor", flow: "ContinuousFlatRateManagementFeeTrackerBeaconFactory_constructor", startNode: "ContinuousFlatRateManagementFeeTrackerBeaconFactory.constructor"},
            { name: "▶️ setImplementation", flow: "", startNode: "ContinuousFlatRateManagementFeeTrackerBeaconFactory.setImplementation"},
            { name: "▶️ ddeployProxy", flow: "", startNode: "ContinuousFlatRateManagementFeeTrackerBeaconFactory.deployProxy"},
          ],
          // 12.  SLOC 772
          "ContinuousFlatRateManagementFeeTracker": [
            { name: "🔎 SHARES", flow: "", startNode: "ContinuousFlatRateManagementFeeTracker.SHARES"},
            { name: "🔎 getLastSettled", flow: "", startNode: "ContinuousFlatRateManagementFeeTracker.getLastSettled"},
            { name: "🔎 getRate", flow: "", startNode: "ContinuousFlatRateManagementFeeTracker.getRate"},
            { name: "▶️ constructor", flow: "", startNode: "ContinuousFlatRateManagementFeeTracker.constructor"},
            { name: "▶️ resetLastSettled", flow: "", startNode: "ContinuousFlatRateManagementFeeTracker.resetLastSettled"},
            { name: "▶️ setRate", flow: "", startNode: "ContinuousFlatRateManagementFeeTracker.setRate"},
            { name: "▶️ settleManagementFee", flow: "", startNode: "ContinuousFlatRateManagementFeeTracker.settleManagementFee"},
          ],
          // 13
          "OpenAccessLimitedCallForwarderBeaconFactory": [
            { name: "🔎 implementation", flow: "", startNode: "OpenAccessLimitedCallForwarderBeaconFactory.implementation"},
            { name: "🔎 GLOBAL", flow: "", startNode: "OpenAccessLimitedCallForwarderBeaconFactory.GLOBAL"},
            { name: "🔎 instanceToShares", flow: "", startNode: "OpenAccessLimitedCallForwarderBeaconFactory.instanceToShares"},
            { name: "🔎 getSharesForInstance", flow: "", startNode: "OpenAccessLimitedCallForwarderBeaconFactory.getSharesForInstance"},
            { name: "▶️ constructor", flow: "OpenAccessLimitedCallForwarderBeaconFactory_constructor", startNode: "OpenAccessLimitedCallForwarderBeaconFactory.constructor"},
            { name: "▶️ ssetImplementation", flow: "", startNode: "OpenAccessLimitedCallForwarderBeaconFactory.setImplementation"},
            { name: "▶️ ddeployProxy", flow: "", startNode: "OpenAccessLimitedCallForwarderBeaconFactory.deployProxy"},
          ],
          // 14.  SLOC 838
          "OpenAccessLimitedCallForwarder": [
            { name: "🔎 SHARES", flow: "", startNode: "OpenAccessLimitedCallForwarder.SHARES"},
            { name: "🔎 OPEN_ACCESS_LIMITED_CALL_FORWARDER", flow: "", startNode: "OpenAccessLimitedCallForwarder.OPEN_ACCESS_LIMITED_CALL_FORWARDER"},
            { name: "🔎 OPEN_ACCESS_LIMITED_CALL_FORWARDER_ID", flow: "", startNode: "OpenAccessLimitedCallForwarder.OPEN_ACCESS_LIMITED_CALL_FORWARDER_ID"},
            { name: "▶️ constructor", flow: "", startNode: "OpenAccessLimitedCallForwarder.constructor"},
            { name: "▶️ canCall", flow: "", startNode: "OpenAccessLimitedCallForwarder.canCall"},
            { name: "▶️ addCall", flow: "", startNode: "OpenAccessLimitedCallForwarder.addCall"},
            { name: "▶️ executeCalls", flow: "", startNode: "OpenAccessLimitedCallForwarder.executeCalls"},
            { name: "▶️ removeCall", flow: "", startNode: "OpenAccessLimitedCallForwarder.removeCall"},
          ],
          // 15
          "LimitedAccessLimitedCallForwarderBeaconFactory": [
            { name: "🔎 implementation", flow: "", startNode: "LimitedAccessLimitedCallForwarderBeaconFactory.implementation"},
            { name: "🔎 GLOBAL", flow: "", startNode: "LimitedAccessLimitedCallForwarderBeaconFactory.GLOBAL"},
            { name: "🔎 instanceToShares", flow: "", startNode: "LimitedAccessLimitedCallForwarderBeaconFactory.instanceToShares"},
            { name: "🔎 getSharesForInstance", flow: "", startNode: "LimitedAccessLimitedCallForwarderBeaconFactory.getSharesForInstance"},
            { name: "▶️ constructor", flow: "LimitedAccessLimitedCallForwarderBeaconFactory_constructor", startNode: "LimitedAccessLimitedCallForwarderBeaconFactory.constructor"},
            { name: "▶️ ssetImplementation", flow: "", startNode: "LimitedAccessLimitedCallForwarderBeaconFactory.setImplementation"},
            { name: "▶️ ddeployProxy", flow: "", startNode: "LimitedAccessLimitedCallForwarderBeaconFactory.deployProxy"},
          ],
          // 16. SLOC  838
          "LimitedAccessLimitedCallForwarder": [
            { name: "🔎 SHARES", flow: "", startNode: "LimitedAccessLimitedCallForwarder.SHARES"},
            { name: "▶️ constructor", flow: "", startNode: "LimitedAccessLimitedCallForwarder.constructor"},
            { name: "🔎 Limited_ACCESS_LIMITED_CALL_FORWARDER", flow: "", startNode: "LimitedAccessLimitedCallForwarder.Limited_ACCESS_LIMITED_CALL_FORWARDER"},
            { name: "🔎 Limited_ACCESS_LIMITED_CALL_FORWARDER_ID", flow: "", startNode: "LimitedAccessLimitedCallForwarder.Limited_ACCESS_LIMITED_CALL_FORWARDER_ID"},
            { name: "▶️ canCall", flow: "", startNode: "LimitedAccessLimitedCallForwarder.canCall"},
            { name: "▶️ addCall", flow: "", startNode: "LimitedAccessLimitedCallForwarder.addCall"},
            { name: "▶️ executeCalls", flow: "", startNode: "LimitedAccessLimitedCallForwarder.executeCalls"},
            { name: "▶️ removeCall", flow: "", startNode: "LimitedAccessLimitedCallForwarder.removeCall"},
          ],
          // 17
          "AccountERC20TrackerBeaconFactory": [
            { name: "🔎 implementation", flow: "", startNode: "AccountERC20TrackerBeaconFactory.implementation"},
            { name: "🔎 GLOBAL", flow: "", startNode: "AccountERC20TrackerBeaconFactory.GLOBAL"},
            { name: "🔎 instanceToShares", flow: "", startNode: "AccountERC20TrackerBeaconFactory.instanceToShares"},
            { name: "🔎 getSharesForInstance", flow: "", startNode: "AccountERC20TrackerBeaconFactory.getSharesForInstance"},
            { name: "▶️ constructor", flow: "AccountERC20TrackerBeaconFactory_constructor", startNode: "AccountERC20TrackerBeaconFactory.constructor"},
            { name: "▶️ setImplementation", flow: "", startNode: "AccountERC20TrackerBeaconFactory.setImplementation"},
            { name: "▶️ deployProxy", flow: "", startNode: "AccountERC20TrackerBeaconFactory.deployProxy"},
          ],
          // 18. SLOC  1304
          "AccountERC20Tracker": [
            { name: "🔎 SHARES", flow: "", startNode: "AccountERC20Tracker.SHARES"},
            { name: "🔎 getAccount", flow: "", startNode: "AccountERC20Tracker.getAccount"},
            { name: "🔎 getAssets", flow: "", startNode: "AccountERC20Tracker.getAssets"},
            { name: "🔎 getPositionValue", flow: "", startNode: "AccountERC20Tracker.getPositionValue"},
            { name: "🔎 isAsset", flow: "", startNode: "AccountERC20Tracker.isAsset"},
            { name: "▶️ constructor", flow: "", startNode: "AccountERC20Tracker.constructor"},
            { name: "▶️ addAsset", flow: "", startNode: "AccountERC20Tracker.addAsset"},
            { name: "▶️ init", flow: "", startNode: "AccountERC20Tracker.init"},
            { name: "▶️ removeAsset", flow: "", startNode: "AccountERC20Tracker.removeAsset"},
          ],
          // 19
          "LinearCreditDebtTrackerBeaconFactory": [
            { name: "🔎 implementation", flow: "", startNode: "LinearCreditDebtTrackerBeaconFactory.implementation"},
            { name: "🔎 GLOBAL", flow: "", startNode: "LinearCreditDebtTrackerBeaconFactory.GLOBAL"},
            { name: "🔎 instanceToShares", flow: "", startNode: "LinearCreditDebtTrackerBeaconFactory.instanceToShares"},
            { name: "🔎 getSharesForInstance", flow: "", startNode: "LinearCreditDebtTrackerBeaconFactory.getSharesForInstance"},
            { name: "▶️ constructor", flow: "LinearCreditDebtTrackerBeaconFactory_constructor", startNode: "LinearCreditDebtTrackerBeaconFactory.constructor"},
            { name: "▶️ setImplementation", flow: "", startNode: "LinearCreditDebtTrackerBeaconFactory.setImplementation"},
            { name: "▶️ ddeployProxy", flow: "", startNode: "LinearCreditDebtTrackerBeaconFactory.deployProxy"},
          ],
          // 20. SLOC  808
          "LinearCreditDebtTracker": [
            { name: "🔎 SHARES", flow: "", startNode: "LinearCreditDebtTracker.SHARES"},
            { name: "🔎 getItem", flow: "", startNode: "LinearCreditDebtTracker.getItem"},
            { name: "🔎 getItemIds", flow: "", startNode: "LinearCreditDebtTracker.getItemIds"},
            { name: "🔎 getItemsCount", flow: "", startNode: "LinearCreditDebtTracker.getItemsCount"},
            { name: "🔎 getLastItemId", flow: "", startNode: "LinearCreditDebtTracker.getLastItemId"},
            { name: "🔎 getPositionValue", flow: "", startNode: "LinearCreditDebtTracker.getPositionValue"},
            { name: "▶️ constructor", flow: "", startNode: "LinearCreditDebtTracker.constructor"},
            { name: "▶️ calcItemValue", flow: "", startNode: "LinearCreditDebtTracker.calcItemValue"},
            { name: "▶️ addItem", flow: "", startNode: "LinearCreditDebtTracker.addItem"},
            { name: "▶️ removeItem", flow: "", startNode: "LinearCreditDebtTracker.removeItem"},
            { name: "▶️ updateSettledValue", flow: "", startNode: "LinearCreditDebtTracker.updateSettledValue"},
          ],
          // 21. SLOC 442
          "Global": [
            { name: "🔎 UPGRADE_INTERFACE_VERSION", flow: "", startNode: "Global.UPGRADE_INTERFACE_VERSION"},
            { name: "🔎 proxiableUUID", flow: "", startNode: "Global.proxiableUUID"},
            { name: "🔎 owner", flow: "", startNode: "Global.owner"},
            { name: "🔎 pendingOwner", flow: "", startNode: "Global.pendingOwner"},
            { name: "▶️ acceptOwnership", flow: "", startNode: "Global.acceptOwnership"},
            { name: "▶️ renounceOwnership", flow: "", startNode: "Global.renounceOwnership"},
            { name: "▶️ transferOwnership", flow: "", startNode: "Global.transferOwnership"},
            { name: "▶️ upgradeToAndCall", flow: "", startNode: "Global.upgradeToAndCall"},
            { name: "▶️ init", flow: "", startNode: "Global.init"},
          ],
          // 22. SLOC 23
          "OneToOneAggregator": [
            { name: "🔎 decimals", flow: "", startNode: "OneToOneAggregator.decimals"},
            { name: "🔎 latestRoundData", flow: "", startNode: "OneToOneAggregator.latestRoundData"},
          ],
          "e2e": [
            { name: "▶️ test_deposit_withdraw", flow: "test_deposit_withdraw", startNode: "Users.alice"},
          ],
        };

        function clearAllHighlights() {
            if (!graph) return;
            graph.selectAll("g.node, g.edge").classed("dimmed highlight", false);
            graph.selectAll(".highlight-path, .node-start, .node-active, .path-viewed")
                 .classed("highlight-path node-start node-active path-viewed", false);
            graph.selectAll("g.edge").style("--edge-color", null);
            graph.selectAll('g.node polygon').classed('search-highlight', false);
        }

        function resetAllModes() {
            clearAllHighlights();
            animationState = { isPlaying: false, isPaused: false, currentStep: 0, sequence: [], flowName: null, startNode: null };
            container.classed("animation-playing", false);
            playPauseButton.html("▶️");
        }

        function scrollToNode(nodeName) {
            const nodeElement = graph.selectAll('g.node').filter(function() {
                return d3.select(this).select('title').text() === nodeName;
            }).node();

            if (nodeElement) {
                nodeElement.scrollIntoView({
                    behavior: 'smooth',
                    block: 'center',
                    inline: 'center'
                });
            }
        }

        function highlightSingleNode(nodeName) {
            resetAllModes();
            const nodeElement = graph.selectAll('g.node').filter(function() {
                return d3.select(this).select('title').text() === nodeName;
            }).node();

            if (nodeElement) {
                scrollToNode(nodeName);
                graph.selectAll("g.node, g.edge").classed("dimmed", true);
                d3.select(nodeElement)
                  .classed("dimmed", false)
                  .classed("highlight", true);
            } else {
                console.error("Node to highlight not found:", nodeName);
            }
        }

        async function startAnimation(flowName, startNode) {
            if (!flowName || !startNode) return;
            const startNodeElement = graph.selectAll('g.node').filter(function() {
                return d3.select(this).select('title').text() === startNode;
            }).node();

            if (!startNodeElement) {
                console.error("Start node for animation not found:", startNode);
                return;
            }

            scrollToNode(startNode);
            resetAllModes();
            container.classed("animation-playing", true);
            graph.selectAll("g.node, g.edge").classed("dimmed", true);

            animationState.isPlaying = true;
            animationState.isPaused = false;
            animationState.flowName = flowName;
            animationState.startNode = startNodeElement;

            const edges = graph.selectAll(`g.edge[id^="flow-${flowName}-step-"]`).nodes();
            edges.sort((a, b) => parseInt(a.id.split('-').pop(), 10) - parseInt(b.id.split('-').pop(), 10));

            animationState.sequence = edges.map(edge => {
                const targetTitle = d3.select(edge).select("title").text().split("->")[1].trim();
                const targetNode = graph.selectAll(".node").filter(function() {
                    return d3.select(this).select("title").text() === targetTitle;
                }).node();
                const originalColor = d3.select(edge).select('path').attr('stroke');
                return { edge, targetNode, originalColor };
            });

            d3.select(startNodeElement).classed("highlight node-start", true).classed("dimmed", false);
            playPauseButton.html("⏸️");
            await runAnimation();
        }

        async function runAnimation() {
            while (animationState.currentStep < animationState.sequence.length) {
                if (animationState.isPaused) return;
                animateStep(animationState.currentStep);
                await new Promise(resolve => setTimeout(resolve, animationSpeed));
                animationState.currentStep++;
            }
            if (animationState.currentStep >= animationState.sequence.length) {
                animationState.isPaused = true;
                playPauseButton.html("▶️");
            }
        }

        function animateStep(step) {
            if (step > 0) {
                const prev = animationState.sequence[step - 1];
                d3.select(prev.edge).classed("highlight-path", false).classed("path-viewed", true);
                d3.select(prev.targetNode).classed("node-active", false).classed("highlight", true);
            }
            const current = animationState.sequence[step];
            if (!current) return;

            d3.select(current.edge).style("--edge-color", current.originalColor);
            d3.select(current.edge).classed("highlight-path", true).classed("dimmed", false);
            d3.select(current.targetNode).classed("highlight node-active", true).classed("dimmed", false);
        }

        function togglePlayPause() {
            if (!animationState.isPlaying) return;
            animationState.isPaused = !animationState.isPaused;
            playPauseButton.html(animationState.isPaused ? "▶️" : "⏸️");
            if (!animationState.isPaused) runAnimation();
        }

        function stepForward() {
            if (!animationState.isPlaying || animationState.currentStep >= animationState.sequence.length) return;
            if (!animationState.isPaused) togglePlayPause();
            animateStep(animationState.currentStep);
            animationState.currentStep++;
        }

        function stepBackward() {
            if (!animationState.isPlaying || animationState.currentStep <= 0) return;
            if (!animationState.isPaused) togglePlayPause();

            animationState.currentStep--;
            const stepToUndo = animationState.sequence[animationState.currentStep];
            d3.select(stepToUndo.edge).classed("highlight-path path-viewed", false).style("--edge-color", null);
            d3.select(stepToUndo.targetNode).classed("highlight node-active", false);

            if (animationState.currentStep > 0) {
                const stepToReactivate = animationState.sequence[animationState.currentStep - 1];
                d3.select(stepToReactivate.edge)
                    .style("--edge-color", stepToReactivate.originalColor)
                    .classed("highlight-path", true)
                    .classed("path-viewed", false);
                d3.select(stepToReactivate.targetNode).classed("node-active", true);
            } else {
                 d3.select(animationState.startNode).classed("highlight node-start", true);
            }
        }

        const controls = container.append("div").attr("class", "graph-controls");
        const searchInput = controls.append("input").attr("type", "text").attr("placeholder", "Search nodes...");
        const contractSelect = controls.append("select");
        const actionSelect = controls.append("select");

        function populateActions(contractKey) {
            const actions = animationTriggers[contractKey] || [];
            actionSelect.html(""); // Clear previous options

            // Add placeholder and then bind data
            actionSelect.append("option").text("Select Action...").attr("value", "").property("selected", true);
            actionSelect.selectAll("option.action-item")
                .data(actions)
                .enter()
                .append("option")
                .attr("class", "action-item")
                .text(d => d.name)
                .attr("data-flow", d => d.flow ?? null)
                .attr("data-start-node", d => d.startNode);
        }

        contractSelect.append("option").text("Select Contract...").attr("value", "").property("selected", true);
        Object.keys(animationTriggers).forEach(key => {
            contractSelect.append("option").text(key).attr("value", key);
        });

        contractSelect.on("change", function() {
            const contractKey = this.value;
            populateActions(contractKey);

            if (contractKey) {
                const clusterTitle = `cluster_${contractKey}`;
                const clusterElement = graph.selectAll('g.cluster').filter(function() {
                    return d3.select(this).select('title').text() === clusterTitle;
                }).node();

                if (clusterElement) {
                    clusterElement.scrollIntoView({
                        behavior: 'smooth',
                        block: 'center',
                        inline: 'center'
                    });

                    resetAllModes();
                    graph.selectAll("g.node, g.edge, g.cluster").classed("dimmed", true);

                    const clusterSelection = d3.select(clusterElement);
                    clusterSelection.classed("dimmed", false).classed("highlight", true);
                    // Also un-dim everything inside the cluster
                    clusterSelection.selectAll('g').classed('dimmed', false);
                }
            } else {
                resetAllModes();
            }
        });

        actionSelect.on("change", function() {
            const selectedOption = d3.select(this).select("option:checked");
            const flow = selectedOption.attr("data-flow");
            const startNode = selectedOption.attr("data-start-node");

            if (!startNode) return;

            if (currentMode !== 'animation') {
                d3.select(".mode-selector button[data-mode='animation']").dispatch('click');
            }

            if (flow && flow !== 'null') {
                startAnimation(flow, startNode);
            } else {
                highlightSingleNode(startNode);
            }

            this.selectedIndex = 0; // Only reset action dropdown
        });

        populateActions("");

        const modeSelector = controls.append("div").attr("class", "mode-selector");
        const modes = [
            { key: 'explore', text: '🔎 Explore' }, { key: 'animation', text: '▶️ Animate' }
        ];

        modeSelector.selectAll("button").data(modes).enter().append("button")
            .attr("data-mode", d => d.key)
            .classed("active", d => d.key === currentMode)
            .html(d => d.text)
            .on("click", function(event, d) {
                const previousMode = currentMode;
                currentMode = d.key;
                modeSelector.selectAll("button").classed("active", false);
                d3.select(this).classed("active", true);
                container.classed("animation-mode-on", currentMode === 'animation');
                if (previousMode === 'animation' && currentMode === 'explore' && (animationState.isPlaying || !graph.select('.dimmed').empty())) {
                    animationState.isPlaying = false;
                    animationState.isPaused = true;
                    container.classed("animation-playing", false);
                    playPauseButton.html("▶️");
                    const animatedElements = graph.selectAll(".highlight, .path-viewed, .highlight-path, .node-start, .node-active");
                    animatedElements
                        .classed("path-viewed highlight-path node-start node-active", false)
                        .classed("highlight", true)
                        .classed("dimmed", false);
                    graph.selectAll("g.edge.highlight").style("--edge-color", null);
                } else {
                    resetAllModes();
                }
            });

        const playbackControls = controls.append("div").attr("class", "playback-controls");
        const stepBackButton = playbackControls.append("button").html("⏪").on("click", stepBackward);
        const playPauseButton = playbackControls.append("button").html("▶️").on("click", togglePlayPause);
        const stepForwardButton = playbackControls.append("button").html("⏭️").on("click", stepForward);
        const resetButton = playbackControls.append("button").html("⏹️").on("click", resetAllModes);

        playbackControls.append("label").text("Speed:");
        const speedSelect = playbackControls.append("select")
            .on("change", function() { animationSpeed = parseInt(this.value, 10); });
        speedSelect.selectAll("option")
            .data([{ val: 1500, txt: "Slow" }, { val: 1000, txt: "Normal" }, { val: 500, txt: "Fast" }])
            .enter().append("option")
            .attr("value", d => d.val)
            .property("selected", d => d.val === 1000)
            .text(d => d.txt);

        const fullscreenButton = controls.append("button")
            .attr("class", "fullscreen-button")
            .html("⛶ Fullscreen (k)")
            .on("click", toggleFullScreen);

        function toggleFullScreen() {
            if (!document.fullscreenElement) {
                graphContainerElement.requestFullscreen().catch(err => {
                    alert(`Error attempting to enable full-screen mode: ${err.message} (${err.name})`);
                });
            } else {
                document.exitFullscreen();
            }
        }

        document.addEventListener("fullscreenchange", () => {
            if (document.fullscreenElement === graphContainerElement) {
                container.classed("fullscreen", true);
                fullscreenButton.html("Exit Fullscreen (k)");
            } else {
                container.classed("fullscreen", false);
                fullscreenButton.html("⛶ Fullscreen (k)");
            }
        });

        document.addEventListener("keyup", (event) => {
            if (event.target.tagName === 'INPUT' || event.target.tagName === 'SELECT') return;
            if (event.key.toLowerCase() === 'k') {
                event.preventDefault();
                toggleFullScreen();
            }
        });

        fetch(dotUrl).then(response => response.text()).then(dotSource => {
            container.graphviz().renderDot(dotSource).on("end", function() {
                graph = container;

                // --- NEW: Search input functionality ---
                searchInput.on("input", function() {
                    const searchTerm = this.value.toLowerCase().trim();
                    graph.selectAll('g.node polygon').classed('search-highlight', false);

                    if (searchTerm === "") {
                        // If search is cleared, remove any dimming.
                        graph.selectAll('g.node, g.edge, g.cluster').classed('dimmed', false);
                        return;
                    }

                    // Dim all nodes and edges to make search results stand out.
                    graph.selectAll('g.node, g.edge, g.cluster').classed('dimmed', true);

                    let firstMatch = null;

                    graph.selectAll('g.node').each(function() {
                        const node = d3.select(this);
                        const title = node.select('title').text().toLowerCase();
                        if (title.includes(searchTerm)) {
                            node.classed('dimmed', false); // Un-dim the matched node.
                            node.select('polygon').classed('search-highlight', true);
                            if (!firstMatch) {
                                firstMatch = this; // 'this' is the DOM element.
                            }
                        }
                    });

                    // Also un-dim clusters that contain matched nodes
                    graph.selectAll('g.cluster').each(function() {
                        const cluster = d3.select(this);
                        // Check if any non-dimmed node is within this cluster
                        if (cluster.selectAll('g.node:not(.dimmed)').size() > 0) {
                            cluster.classed('dimmed', false);
                        }
                    });

                    if (firstMatch) {
                        // Scroll the first matched node into view.
                        firstMatch.scrollIntoView({
                            behavior: 'smooth',
                            block: 'center',
                            inline: 'center'
                        });
                    }
                });

                function handleExploreClick(selection) {
                    if (graph.selectAll('.dimmed').empty()) {
                        graph.selectAll('g.node, g.edge').classed('dimmed', true);
                    }
                    const isHighlighted = selection.classed('highlight');
                    selection.classed('highlight', !isHighlighted).classed('dimmed', isHighlighted);
                }

                graph.selectAll('g.node').on('click', function(event) {
                    event.stopPropagation();
                    if (currentMode === 'animation') {
                        if (animationState.isPlaying || !graph.select('.dimmed').empty()) resetAllModes();
                    } else {
                        handleExploreClick(d3.select(this));
                    }
                });

                graph.selectAll('g.edge').on('click', function(event) {
                    event.stopPropagation();
                    if (currentMode !== 'explore') return;
                    handleExploreClick(d3.select(this));
                });

                graph.select("svg").on("click", () => {
                    if (currentMode === 'explore') {
                        if (!graph.select('.dimmed').empty()) {
                            if (confirm('Reset view? This will clear your current selection.')) {
                                resetAllModes();
                            }
                        }
                    } else {
                        resetAllModes();
                    }
                });
            });
        });
    }
    setupGraph("graph", "protocol-onyx.dot");
});
</script>

## Usage
This interactive graph helps you visualize the call flows within the UniswapV2 protocol. There are two main modes you can use:

### ▶️ Animate Mode (Default)
This mode is designed to automatically play predefined critical flows or highlight specific items.

-   **How it works**: Use the dropdown menus at the top to select a contract and then a specific action. The graph will automatically scroll to the relevant node.
    -   Actions marked with **▶️** will play a full animation of a call sequence.
    -   Actions marked with **🔎** will highlight a single function or storage variable.
-   **Playback Controls**: For animations, you can use the controls to play/pause (▶️/⏸️), step forward (⏭️), step backward (⏪), and stop/reset (⏹️).

---
### 🔎 Explore Mode
This mode allows for free-form exploration of the contract interactions.

-   **How it works**: After switching to Explore mode, simply click on any node or edge to highlight it. The first click will dim the rest of the graph, allowing you to build a custom path.
-   **Building Paths**: Continue clicking on elements to add them to your highlighted path or click on an already highlighted element to de-select it.
-   **Resetting**: To clear your selection, click on the blank background of the graph and confirm the reset prompt.

---
### Combining Modes: Animation to Exploration
You can seamlessly transition from a guided animation/highlight to free-form exploration.

1.  **Start in Animate Mode** and select an action from the dropdowns.
2.  Once the animation is complete/paused or the node is highlighted, switch to **Explore Mode**.
3.  The highlighted path or node will **remain visible**.
4.  You can now **add to this path** by clicking on other dimmed nodes/edges, or remove parts of it by clicking on highlighted elements.

## Security Advisory

## Admins

1. Admin must not use non Standard ERC20
  - Rebasing
  - Fee on Tranfer Tokens
  - Re-entrace callbacks
2. An admin must not execute deposit/redeem requests for tiny shares amounts
3. Succeptability to high market volatility.
4. Caefully about seting assets
5. Asset or Tokenized Value. must not be a volatile asset. since price has to be update manually. This is innefiicient and gas intenisve and maybe unresponsive.
