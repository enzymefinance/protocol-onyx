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

/// @notice Deploys core Onyx protocol contracts to a target network
///         and writes their addresses to `deployments/${chainid}.json` for front-end consumption.
contract DeployProtocol is Script {
    struct Addrs {
        ERC1967Proxy globalProxy;
        Global global;
        BeaconFactory sharesBeaconFactory;
        ComponentBeaconFactory feeHandlerBeaconFactory;
        ComponentBeaconFactory continuousFlatRateManagementFeeTrackerBeaconFactory;
        ComponentBeaconFactory continuousFlatRatePerformanceFeeTrackerBeaconFactory;
        ComponentBeaconFactory valuationHandlerBeaconFactory;
        ComponentBeaconFactory accountERC20TrackerFactory;
        ComponentBeaconFactory linearCreditDebtTrackerBeaconFactory;
        ComponentBeaconFactory erc7540LikeDepositQueueBeaconFactory;
        ComponentBeaconFactory erc7540LikeRedeemQueueBeaconFactory;
        ComponentBeaconFactory limitedAccessLimitedCallForwarderFactory;
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
    }

    Addrs public addrs;

    function run() external {
        uint256 deployerPK = vm.envUint("DEPLOYER_PK");
        vm.startBroadcast(deployerPK);

        /* ---------------------------------------------------------------------
         * Core governance / global contract
         * -------------------------------------------------------------------*/

        // Deploy as proxy
        addrs.global = new Global();
        addrs.globalProxy = new ERC1967Proxy({
            implementation: address(addrs.global),
            _data: abi.encodeWithSelector(Global.init.selector, vm.addr(deployerPK))
        });

        /* ---------------------------------------------------------------------
         * Factories (upgrade beacons)
         * -------------------------------------------------------------------*/
        addrs.sharesBeaconFactory = new BeaconFactory(address(addrs.globalProxy));
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

        vm.stopBroadcast();

        /* ---------------------------------------------------------------------
         * Persist addresses to JSON
         * -------------------------------------------------------------------*/
        string memory path = string.concat("./deploy/", vm.toString(block.chainid), ".json");
        string memory json = string.concat(
            "{\n",
            '  "GlobalProxy": "',
            vm.toString(address(addrs.globalProxy)),
            '",\n',
            '  "Global": "',
            vm.toString(address(addrs.global)),
            '",\n',
            '  "SharesFactory": "',
            vm.toString(address(addrs.sharesBeaconFactory)),
            '",\n',
            '  "FeeHandlerFactory": "',
            vm.toString(address(addrs.feeHandlerBeaconFactory)),
            '",\n',
            '  "ContinuousFlatRateManagementFeeTrackerFactory": "',
            vm.toString(address(addrs.continuousFlatRateManagementFeeTrackerBeaconFactory)),
            '",\n',
            '  "ContinuousFlatRatePerformanceFeeTrackerFactory": "',
            vm.toString(address(addrs.continuousFlatRatePerformanceFeeTrackerBeaconFactory)),
            '",\n',
            '  "ValuationHandlerFactory": "',
            vm.toString(address(addrs.valuationHandlerBeaconFactory)),
            '",\n',
            '  "AccountERC20TrackerFactory": "',
            vm.toString(address(addrs.accountERC20TrackerFactory)),
            '",\n',
            '  "LinearCreditDebtTrackerFactory": "',
            vm.toString(address(addrs.linearCreditDebtTrackerBeaconFactory)),
            '",\n',
            '  "ERC7540LikeDepositQueueFactory": "',
            vm.toString(address(addrs.erc7540LikeDepositQueueBeaconFactory)),
            '",\n',
            '  "ERC7540LikeRedeemQueueFactory": "',
            vm.toString(address(addrs.erc7540LikeRedeemQueueBeaconFactory)),
            '",\n',
            '  "LimitedAccessLimitedCallForwarderFactory": "',
            vm.toString(address(addrs.limitedAccessLimitedCallForwarderFactory)),
            '",\n',
            '  "SharesLib": "',
            vm.toString(address(addrs.shares)),
            '",\n',
            '  "FeeHandlerLib": "',
            vm.toString(address(addrs.feeHandler)),
            '",\n',
            '  "ContinuousFlatRateManagementFeeTrackerLib": "',
            vm.toString(address(addrs.continuousFlatRateManagementFeeTracker)),
            '",\n',
            '  "ContinuousFlatRatePerformanceFeeTrackerLib": "',
            vm.toString(address(addrs.continuousFlatRatePerformanceFeeTracker)),
            '",\n',
            '  "ValuationHandlerLib": "',
            vm.toString(address(addrs.valuationHandler)),
            '",\n',
            '  "AccountERC20TrackerLib": "',
            vm.toString(address(addrs.accountERC20Tracker)),
            '",\n',
            '  "LinearCreditDebtTrackerLib": "',
            vm.toString(address(addrs.linearCreditDebtTracker)),
            '",\n',
            '  "ERC7540LikeDepositQueueLib": "',
            vm.toString(address(addrs.erc7540LikeDepositQueue)),
            '",\n',
            '  "ERC7540LikeRedeemQueueLib": "',
            vm.toString(address(addrs.erc7540LikeRedeemQueue)),
            '",\n',
            '  "LimitedAccessLimitedCallForwarderLib": "',
            vm.toString(address(addrs.limitedAccessLimitedCallForwarder)),
            '"\n',
            "}\n"
        );

        vm.writeFile(path, json);
        console2.log("Deployment artifacts written to", path);
    }
}
