// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import {Global} from "src/global/Global.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BeaconFactory} from "src/factories/BeaconFactory.sol";
import {ComponentBeaconFactory} from "src/factories/ComponentBeaconFactory.sol";
import {Shares} from "src/shares/Shares.sol";
import {FeeHandler} from "src/components/fees/FeeHandler.sol";
import {
    ContinuousFlatRateManagementFeeTracker
} from "src/components/fees/management-fee-trackers/ContinuousFlatRateManagementFeeTracker.sol";
import {
    ContinuousFlatRatePerformanceFeeTracker
} from "src/components/fees/performance-fee-trackers/ContinuousFlatRatePerformanceFeeTracker.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {LinearCreditDebtTracker} from "src/components/value/position-trackers/LinearCreditDebtTracker.sol";
import {ERC7540LikeDepositQueue} from "src/components/issuance/deposit-handlers/ERC7540LikeDepositQueue.sol";
import {ERC7540LikeRedeemQueue} from "src/components/issuance/redeem-handlers/ERC7540LikeRedeemQueue.sol";
import {AccountERC20Tracker} from "src/components/value/position-trackers/AccountERC20Tracker.sol";
import {LimitedAccessLimitedCallForwarder} from "src/components/roles/LimitedAccessLimitedCallForwarder.sol";
import {CreWorkflowConsumer} from "src/components/automations/chainlink-cre/CreWorkflowConsumer.sol";
import {SharesOwnedAddressList} from "src/components/lists/SharesOwnedAddressList.sol";
import {OwnableAddressList} from "src/infra/lists/address-list/OwnableAddressList.sol";
import {SyncDepositHandler} from "src/components/issuance/deposit-handlers/SyncDepositHandler.sol";

/// @notice Deploys core Onyx protocol contracts to a target network
///         and writes their addresses to `deployments/${chainid}.json` for front-end consumption.
contract DeployProtocol is Script {
    address constant ENZYME_DEVELOPERS = address(0xd24bBcD06C54a5a2A6d22f4AaE25AB511190C7b5);

    struct Addrs {
        ERC1967Proxy globalProxy;
        Global global;
        BeaconFactory sharesBeaconFactory;
        BeaconFactory ownableAddressListFactory;
        ComponentBeaconFactory feeHandlerBeaconFactory;
        ComponentBeaconFactory continuousFlatRateManagementFeeTrackerBeaconFactory;
        ComponentBeaconFactory continuousFlatRatePerformanceFeeTrackerBeaconFactory;
        ComponentBeaconFactory valuationHandlerBeaconFactory;
        ComponentBeaconFactory accountERC20TrackerFactory;
        ComponentBeaconFactory linearCreditDebtTrackerBeaconFactory;
        ComponentBeaconFactory erc7540LikeDepositQueueBeaconFactory;
        ComponentBeaconFactory erc7540LikeRedeemQueueBeaconFactory;
        ComponentBeaconFactory limitedAccessLimitedCallForwarderFactory;
        ComponentBeaconFactory creWorkflowConsumerFactory;
        ComponentBeaconFactory sharesOwnedAddressListFactory;
        ComponentBeaconFactory syncDepositHandlerFactory;
        Shares shares;
        FeeHandler feeHandler;
        ContinuousFlatRateManagementFeeTracker continuousFlatRateManagementFeeTracker;
        ContinuousFlatRatePerformanceFeeTracker continuousFlatRatePerformanceFeeTracker;
        ValuationHandler valuationHandler;
        AccountERC20Tracker accountERC20Tracker;
        LinearCreditDebtTracker linearCreditDebtTracker;
        ERC7540LikeDepositQueue erc7540LikeDepositQueue;
        ERC7540LikeRedeemQueue erc7540LikeRedeemQueue;
        LimitedAccessLimitedCallForwarder limitedAccessLimitedCallForwarder;
        CreWorkflowConsumer creWorkflowConsumer;
        SharesOwnedAddressList sharesOwnedAddressList;
        OwnableAddressList ownableAddressList;
        SyncDepositHandler syncDepositHandler;
    }

    Addrs internal addrs;

    function run() external {
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        /* ---------------------------------------------------------------------
         * Core governance / global contract
         * -------------------------------------------------------------------*/

        // Deploy as proxy
        addrs.global = new Global();
        addrs.globalProxy = new ERC1967Proxy({
            implementation: address(addrs.global), _data: abi.encodeWithSelector(Global.init.selector, deployer)
        });

        /* ---------------------------------------------------------------------
         * Factories (upgrade beacons)
         * -------------------------------------------------------------------*/
        addrs.sharesBeaconFactory = new BeaconFactory(address(addrs.globalProxy));
        addrs.ownableAddressListFactory = new BeaconFactory(address(addrs.globalProxy));
        // Create specialized beacon factories for each component type
        addrs.feeHandlerBeaconFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.continuousFlatRateManagementFeeTrackerBeaconFactory =
            new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.continuousFlatRatePerformanceFeeTrackerBeaconFactory =
            new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.accountERC20TrackerFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.linearCreditDebtTrackerBeaconFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.valuationHandlerBeaconFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.erc7540LikeDepositQueueBeaconFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.erc7540LikeRedeemQueueBeaconFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.limitedAccessLimitedCallForwarderFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        address chainlinkKeystoneForwarder = __getChainlinkKeystoneForwarder();
        bool isChainlinkKeystoneForwarderAvailable = chainlinkKeystoneForwarder != address(0);
        if (isChainlinkKeystoneForwarderAvailable) {
            addrs.creWorkflowConsumerFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        }
        addrs.sharesOwnedAddressListFactory = new ComponentBeaconFactory(address(addrs.globalProxy));
        addrs.syncDepositHandlerFactory = new ComponentBeaconFactory(address(addrs.globalProxy));

        /* ---------------------------------------------------------------------
         * Implementation contracts
         * -------------------------------------------------------------------*/
        addrs.shares = new Shares();
        addrs.feeHandler = new FeeHandler();
        addrs.continuousFlatRateManagementFeeTracker = new ContinuousFlatRateManagementFeeTracker();
        addrs.continuousFlatRatePerformanceFeeTracker = new ContinuousFlatRatePerformanceFeeTracker();
        addrs.valuationHandler = new ValuationHandler();
        addrs.accountERC20Tracker = new AccountERC20Tracker();
        addrs.linearCreditDebtTracker = new LinearCreditDebtTracker();
        addrs.erc7540LikeDepositQueue = new ERC7540LikeDepositQueue();
        addrs.erc7540LikeRedeemQueue = new ERC7540LikeRedeemQueue();
        addrs.limitedAccessLimitedCallForwarder = new LimitedAccessLimitedCallForwarder();
        if (isChainlinkKeystoneForwarderAvailable) {
            addrs.creWorkflowConsumer = new CreWorkflowConsumer(chainlinkKeystoneForwarder, ENZYME_DEVELOPERS);
        }
        addrs.sharesOwnedAddressList = new SharesOwnedAddressList();
        addrs.ownableAddressList = new OwnableAddressList();
        addrs.syncDepositHandler = new SyncDepositHandler();

        /* ---------------------------------------------------------------------
         * Set implementations
         * -------------------------------------------------------------------*/
        // Set implementations for each specialized beacon factory
        addrs.sharesBeaconFactory.setImplementation(address(addrs.shares));
        addrs.feeHandlerBeaconFactory.setImplementation(address(addrs.feeHandler));
        addrs.continuousFlatRateManagementFeeTrackerBeaconFactory
            .setImplementation(address(addrs.continuousFlatRateManagementFeeTracker));
        addrs.continuousFlatRatePerformanceFeeTrackerBeaconFactory
            .setImplementation(address(addrs.continuousFlatRatePerformanceFeeTracker));
        addrs.accountERC20TrackerFactory.setImplementation(address(addrs.accountERC20Tracker));
        addrs.linearCreditDebtTrackerBeaconFactory.setImplementation(address(addrs.linearCreditDebtTracker));
        addrs.valuationHandlerBeaconFactory.setImplementation(address(addrs.valuationHandler));
        addrs.erc7540LikeDepositQueueBeaconFactory.setImplementation(address(addrs.erc7540LikeDepositQueue));
        addrs.erc7540LikeRedeemQueueBeaconFactory.setImplementation(address(addrs.erc7540LikeRedeemQueue));
        addrs.limitedAccessLimitedCallForwarderFactory
            .setImplementation(address(addrs.limitedAccessLimitedCallForwarder));
        if (isChainlinkKeystoneForwarderAvailable) {
            addrs.creWorkflowConsumerFactory.setImplementation(address(addrs.creWorkflowConsumer));
        }
        addrs.sharesOwnedAddressListFactory.setImplementation(address(addrs.sharesOwnedAddressList));
        addrs.ownableAddressListFactory.setImplementation(address(addrs.ownableAddressList));
        addrs.syncDepositHandlerFactory.setImplementation(address(addrs.syncDepositHandler));

        vm.stopBroadcast();

        __writeDeploymentArtifacts();
    }

    function __writeDeploymentArtifacts() private {
        string memory key = "deploy";
        vm.serializeAddress(key, "GlobalProxy", address(addrs.globalProxy));
        vm.serializeAddress(key, "Global", address(addrs.global));
        vm.serializeAddress(key, "SharesFactory", address(addrs.sharesBeaconFactory));
        vm.serializeAddress(key, "FeeHandlerFactory", address(addrs.feeHandlerBeaconFactory));
        vm.serializeAddress(
            key,
            "ContinuousFlatRateManagementFeeTrackerFactory",
            address(addrs.continuousFlatRateManagementFeeTrackerBeaconFactory)
        );
        vm.serializeAddress(
            key,
            "ContinuousFlatRatePerformanceFeeTrackerFactory",
            address(addrs.continuousFlatRatePerformanceFeeTrackerBeaconFactory)
        );
        vm.serializeAddress(key, "ValuationHandlerFactory", address(addrs.valuationHandlerBeaconFactory));
        vm.serializeAddress(key, "AccountERC20TrackerFactory", address(addrs.accountERC20TrackerFactory));
        vm.serializeAddress(key, "LinearCreditDebtTrackerFactory", address(addrs.linearCreditDebtTrackerBeaconFactory));
        vm.serializeAddress(key, "ERC7540LikeDepositQueueFactory", address(addrs.erc7540LikeDepositQueueBeaconFactory));
        vm.serializeAddress(key, "ERC7540LikeRedeemQueueFactory", address(addrs.erc7540LikeRedeemQueueBeaconFactory));
        vm.serializeAddress(
            key, "LimitedAccessLimitedCallForwarderFactory", address(addrs.limitedAccessLimitedCallForwarderFactory)
        );
        vm.serializeAddress(key, "SharesOwnedAddressListFactory", address(addrs.sharesOwnedAddressListFactory));
        vm.serializeAddress(key, "OwnableAddressListFactory", address(addrs.ownableAddressListFactory));
        vm.serializeAddress(key, "SyncDepositHandlerFactory", address(addrs.syncDepositHandlerFactory));
        vm.serializeAddress(key, "SharesLib", address(addrs.shares));
        vm.serializeAddress(key, "FeeHandlerLib", address(addrs.feeHandler));
        vm.serializeAddress(
            key, "ContinuousFlatRateManagementFeeTrackerLib", address(addrs.continuousFlatRateManagementFeeTracker)
        );
        vm.serializeAddress(
            key, "ContinuousFlatRatePerformanceFeeTrackerLib", address(addrs.continuousFlatRatePerformanceFeeTracker)
        );
        vm.serializeAddress(key, "ValuationHandlerLib", address(addrs.valuationHandler));
        vm.serializeAddress(key, "AccountERC20TrackerLib", address(addrs.accountERC20Tracker));
        vm.serializeAddress(key, "LinearCreditDebtTrackerLib", address(addrs.linearCreditDebtTracker));
        vm.serializeAddress(key, "ERC7540LikeDepositQueueLib", address(addrs.erc7540LikeDepositQueue));
        vm.serializeAddress(key, "ERC7540LikeRedeemQueueLib", address(addrs.erc7540LikeRedeemQueue));
        vm.serializeAddress(
            key, "LimitedAccessLimitedCallForwarderLib", address(addrs.limitedAccessLimitedCallForwarder)
        );
        vm.serializeAddress(key, "SharesOwnedAddressListLib", address(addrs.sharesOwnedAddressList));
        vm.serializeAddress(key, "OwnableAddressListLib", address(addrs.ownableAddressList));
        vm.serializeAddress(key, "SyncDepositHandlerLib", address(addrs.syncDepositHandler));
        vm.serializeAddress(key, "CreWorkflowConsumerFactory", address(addrs.creWorkflowConsumerFactory));
        string memory json = vm.serializeAddress(key, "CreWorkflowConsumerLib", address(addrs.creWorkflowConsumer));

        vm.createDir("./deploy", true);
        string memory path = string.concat("./deploy/", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);
        console2.log("Deployment artifacts written to", path);
    }

    function __getChainlinkKeystoneForwarder() private view returns (address) {
        // Ethereum
        if (block.chainid == 1) {
            return 0x0b93082D9b3C7C97fAcd250082899BAcf3af3885;
        }

        // Arbitrum
        if (block.chainid == 42161) {
            return 0xF8344CFd5c43616a4366C34E3EEE75af79a74482;
        }

        // Base
        if (block.chainid == 8453) {
            return 0xF8344CFd5c43616a4366C34E3EEE75af79a74482;
        }

        // Ethereum Sepolia
        if (block.chainid == 11155111) {
            return 0xF8344CFd5c43616a4366C34E3EEE75af79a74482;
        }

        // MegaETH
        if (block.chainid == 4326) {
            return 0x7BCcaFBD064cB3658476066Cc33ceE3F3414c04c;
        }

        return address(0);
    }
}
