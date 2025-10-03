// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";

import {IUSDT} from "./IUSDT.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FeeHandler} from "src/components/fees/FeeHandler.sol";
import {ContinuousFlatRateManagementFeeTracker} from
    "src/components/fees/management-fee-trackers/ContinuousFlatRateManagementFeeTracker.sol";
import {ContinuousFlatRatePerformanceFeeTracker} from
    "src/components/fees/performance-fee-trackers/ContinuousFlatRatePerformanceFeeTracker.sol";
import {ERC7540LikeDepositQueue} from "src/components/issuance/deposit-handlers/ERC7540LikeDepositQueue.sol";
import {ERC7540LikeRedeemQueue} from "src/components/issuance/redeem-handlers/ERC7540LikeRedeemQueue.sol";
import {LimitedAccessLimitedCallForwarder} from "src/components/roles/LimitedAccessLimitedCallForwarder.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {AccountERC20Tracker} from "src/components/value/position-trackers/AccountERC20Tracker.sol";
import {LinearCreditDebtTracker} from "src/components/value/position-trackers/LinearCreditDebtTracker.sol";
import {BeaconFactory} from "src/factories/BeaconFactory.sol";
import {ComponentBeaconFactory} from "src/factories/ComponentBeaconFactory.sol";
import {Global} from "src/global/Global.sol";
import {Global} from "src/global/Global.sol";
import {Shares} from "src/shares/Shares.sol";

contract e2e is Test {
    struct Addrs {
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
    Shares public sharesInstance;
    FeeHandler public feeHandlerInstance;
    ContinuousFlatRateManagementFeeTracker public continuousFlatRateManagementFeeTrackerInstance;
    ContinuousFlatRatePerformanceFeeTracker public continuousFlatRatePerformanceFeeTrackerInstance;
    ValuationHandler public valuationHandlerInstance;
    AccountERC20Tracker public accountERC20TrackerInstance;
    LinearCreditDebtTracker public linearCreditDebtTrackerInstance;
    ERC7540LikeDepositQueue public eRC7540LikeDepositQueueInstance;
    ERC7540LikeRedeemQueue public eRC7540LikeRedeemQueueInstance;
    LimitedAccessLimitedCallForwarder public limitedAccessLimitedCallForwarderInstance;
    IUSDT usdt = IUSDT(address(0xdAC17F958D2ee523a2206206994597C13D831ec7));
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() external {
        vm.createSelectFork("mainnet", 23_466_664 - 1);
        /* ---------------------------------------------------------------------
         * Core governance / global contract
         * -------------------------------------------------------------------*/

        // Deploy as proxy
        address owner = address(this);

        address lib = address(new Global());

        addrs.global = Global(
            address(
                new ERC1967Proxy({
                    implementation: lib,
                    _data: abi.encodeWithSelector(Global.init.selector, address(this))
                })
            )
        );

        /* ---------------------------------------------------------------------
         * Factories (upgrade beacons)
         * -------------------------------------------------------------------*/
        addrs.sharesBeaconFactory = new BeaconFactory(address(addrs.global));

        // Create specialized beacon factories for each component type
        addrs.feeHandlerBeaconFactory = new ComponentBeaconFactory(address(addrs.global));
        addrs.continuousFlatRateManagementFeeTrackerBeaconFactory = new ComponentBeaconFactory(address(addrs.global));
        addrs.continuousFlatRatePerformanceFeeTrackerBeaconFactory = new ComponentBeaconFactory(address(addrs.global));
        addrs.accountERC20TrackerFactory = new ComponentBeaconFactory(address(addrs.global));
        addrs.linearCreditDebtTrackerBeaconFactory = new ComponentBeaconFactory(address(addrs.global));
        addrs.valuationHandlerBeaconFactory = new ComponentBeaconFactory(address(addrs.global));
        addrs.erc7540LikeDepositQueueBeaconFactory = new ComponentBeaconFactory(address(addrs.global));
        addrs.erc7540LikeRedeemQueueBeaconFactory = new ComponentBeaconFactory(address(addrs.global));
        addrs.limitedAccessLimitedCallForwarderFactory = new ComponentBeaconFactory(address(addrs.global));

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
        addrs.continuousFlatRateManagementFeeTrackerBeaconFactory.setImplementation(
            address(addrs.continuousFlatRateManagementFeeTracker)
        );
        addrs.continuousFlatRatePerformanceFeeTrackerBeaconFactory.setImplementation(
            address(addrs.continuousFlatRatePerformanceFeeTracker)
        );
        addrs.accountERC20TrackerFactory.setImplementation(address(addrs.accountERC20Tracker));
        addrs.linearCreditDebtTrackerBeaconFactory.setImplementation(address(addrs.linearCreditDebtTracker));
        addrs.valuationHandlerBeaconFactory.setImplementation(address(addrs.valuationHandler));
        addrs.erc7540LikeDepositQueueBeaconFactory.setImplementation(address(addrs.erc7540LikeDepositQueue));
        addrs.erc7540LikeRedeemQueueBeaconFactory.setImplementation(address(addrs.erc7540LikeRedeemQueue));
        addrs.limitedAccessLimitedCallForwarderFactory.setImplementation(
            address(addrs.limitedAccessLimitedCallForwarder)
        );
    }

    function _deployInstances() internal {
        sharesInstance = Shares(
            addrs.sharesBeaconFactory.deployProxy(
                (
                    abi.encodeWithSignature(
                        "init(address,string,string,bytes32)", address(this), "USDT Shares", "sUSDT", "USDT"
                    )
                )
            )
        );

        feeHandlerInstance = FeeHandler(addrs.feeHandlerBeaconFactory.deployProxy(address(sharesInstance), bytes("")));

        continuousFlatRateManagementFeeTrackerInstance = ContinuousFlatRateManagementFeeTracker(
            addrs.continuousFlatRateManagementFeeTrackerBeaconFactory.deployProxy(address(sharesInstance), bytes(""))
        );

        continuousFlatRatePerformanceFeeTrackerInstance = ContinuousFlatRatePerformanceFeeTracker(
            addrs.continuousFlatRatePerformanceFeeTrackerBeaconFactory.deployProxy(address(sharesInstance), bytes(""))
        );

        valuationHandlerInstance =
            ValuationHandler(addrs.valuationHandlerBeaconFactory.deployProxy(address(sharesInstance), bytes("")));

        accountERC20TrackerInstance =
            AccountERC20Tracker(addrs.accountERC20TrackerFactory.deployProxy(address(sharesInstance), bytes("")));

        linearCreditDebtTrackerInstance = LinearCreditDebtTracker(
            addrs.linearCreditDebtTrackerBeaconFactory.deployProxy(address(sharesInstance), bytes(""))
        );

        eRC7540LikeDepositQueueInstance = ERC7540LikeDepositQueue(
            addrs.erc7540LikeDepositQueueBeaconFactory.deployProxy(address(sharesInstance), bytes(""))
        );

        eRC7540LikeRedeemQueueInstance = ERC7540LikeRedeemQueue(
            addrs.erc7540LikeRedeemQueueBeaconFactory.deployProxy(address(sharesInstance), bytes(""))
        );

        limitedAccessLimitedCallForwarderInstance = LimitedAccessLimitedCallForwarder(
            addrs.limitedAccessLimitedCallForwarderFactory.deployProxy(address(sharesInstance), bytes(""))
        );

        /// Admin Initial

        sharesInstance.setValuationHandler(address(valuationHandlerInstance));
        // sharesInstance.setFeeHandler(address(feeHandlerInstance));
        sharesInstance.addDepositHandler(address(eRC7540LikeDepositQueueInstance));
        sharesInstance.addRedeemHandler(address(eRC7540LikeRedeemQueueInstance));

        uint128 rate = 1e18; // 1e6/1 usdt= 1e18/ 1 Share

        valuationHandlerInstance.setAssetRate(
            ValuationHandler.AssetRateInput({asset: address(usdt), rate: rate, expiry: uint40(block.timestamp + 1)})
        );

        eRC7540LikeDepositQueueInstance.setAsset(address(usdt));
        eRC7540LikeRedeemQueueInstance.setAsset(address(usdt));
    }

    function test_deposit_withdraw() public {
        _deployInstances();

        vm.startPrank(alice);
        deal(address(usdt), alice, 1 * 10 ** usdt.decimals(), true);
        usdt.approve(address(eRC7540LikeDepositQueueInstance), type(uint256).max);
        (uint256 requestId1) = eRC7540LikeDepositQueueInstance.requestDeposit(1e6, alice, alice);
        vm.stopPrank();

        uint256[] memory requestId = new uint256[](1);
        requestId[0] = requestId1;
        eRC7540LikeDepositQueueInstance.executeDepositRequests(requestId);

        vm.startPrank(alice);
        sharesInstance.approve(address(eRC7540LikeRedeemQueueInstance), type(uint256).max);
        (uint256 requestId2) = eRC7540LikeRedeemQueueInstance.requestRedeem(1e18, alice, alice);
        vm.stopPrank();

        requestId[0] = requestId2;
        eRC7540LikeRedeemQueueInstance.executeRedeemRequests(requestId);
    }
}
