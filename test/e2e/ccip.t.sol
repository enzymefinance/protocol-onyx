// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CCIPLocalSimulator} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {MockCCIPRouter} from "@chainlink/local/src/vendor/chainlink-ccip/test/mocks/MockRouter.sol";
import {WETH9} from "@chainlink/local/src/shared/WETH9.sol";
import {IRouterClient} from "@chainlink-ccip/interfaces/IRouterClient.sol";
import {IRouterClient as IRouterClientLocal} from "@chainlink-ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink-ccip/libraries/Client.sol";

import {DepositorWallet} from "src/ccip/DepositorWallet.sol";
import {WalletsManager} from "src/components/ccip/WalletsManager.sol";
import {ERC7540LikeDepositQueue} from "src/components/issuance/deposit-handlers/ERC7540LikeDepositQueue.sol";
import {SyncDepositHandler} from "src/components/issuance/deposit-handlers/SyncDepositHandler.sol";
import {OpenAccessLimitedCallForwarder} from "src/components/roles/OpenAccessLimitedCallForwarder.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {DeterministicBeaconFactory} from "src/factories/DeterministicBeaconFactory.sol";
import {Global} from "src/global/Global.sol";
import {Shares} from "src/shares/Shares.sol";

import {ERC7540LikeDepositQueueHarness} from "test/harnesses/ERC7540LikeDepositQueueHarness.sol";
import {LimitedAccessLimitedCallForwarderHarness} from "test/harnesses/LimitedAccessLimitedCallForwarderHarness.sol";
import {SyncDepositHandlerHarness} from "test/harnesses/SyncDepositHandlerHarness.sol";
import {ValuationHandlerHarness} from "test/harnesses/ValuationHandlerHarness.sol";
import {WalletsManagerHarness} from "test/harnesses/WalletsManagerHarness.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract CCIPE2ETest is TestHelpers {
    CCIPLocalSimulator ccipLocalSimulator;
    address router;
    address wrappedNative;
    uint64 chainSelector;

    Shares shares;
    address owner;
    address admin = makeAddr("admin");

    WalletsManagerHarness walletsManager;
    ValuationHandlerHarness valuationHandler;
    DeterministicBeaconFactory factory;

    MockERC20 depositAsset;

    address user = makeAddr("user");
    uint256 depositAmount = 100e6;
    uint256 expectedShares = 100e18;
    uint256 ccipFee = 0.1 ether;

    function setUp() public {
        vm.warp(100);

        // Deploy CCIP local simulator
        ccipLocalSimulator = new CCIPLocalSimulator();
        (uint64 chainSelector_, IRouterClientLocal sourceRouter,, WETH9 wrappedNative_,,,) =
            ccipLocalSimulator.configuration();
        chainSelector = chainSelector_;
        router = address(sourceRouter);
        wrappedNative = address(wrappedNative_);

        // Set non-zero CCIP fee on mock router
        MockCCIPRouter(payable(router)).setFee(ccipFee);

        // Deploy Shares and add admin
        shares = createShares();
        owner = shares.owner();
        vm.prank(owner);
        shares.addAdmin(admin);

        // Deploy deposit asset
        depositAsset = new MockERC20(6);

        // Deploy and configure ValuationHandler
        valuationHandler = new ValuationHandlerHarness(address(shares));
        vm.prank(admin);
        shares.setValuationHandler(address(valuationHandler));

        valuationHandler.harness_setLastShareValue({_shareValue: 1e18, _timestamp: block.timestamp});
        vm.prank(admin);
        valuationHandler.setAssetRate(
            ValuationHandler.AssetRateInput({
                asset: address(depositAsset), rate: 1e18, expiry: uint40(type(uint40).max)
            })
        );

        // Deploy Global, factory, DepositorWallet impl
        Global global = new Global();
        global.init({_owner: address(this)});

        factory = new DeterministicBeaconFactory({_global: address(global)});
        DepositorWallet depositorWalletImpl = new DepositorWallet(router);
        factory.setImplementation(address(depositorWalletImpl));

        // Deploy WalletsManager
        walletsManager = new WalletsManagerHarness(address(shares), router, address(factory));
    }

    //==================================================================================================================
    // Deposit handler setup helpers
    //==================================================================================================================

    function __deploySyncDepositHandler() internal returns (SyncDepositHandlerHarness depositHandler_) {
        depositHandler_ = new SyncDepositHandlerHarness(address(shares));
        depositHandler_.init(address(depositAsset));

        vm.prank(admin);
        shares.addDepositHandler(address(depositHandler_));

        vm.prank(admin);
        depositHandler_.setMaxSharePriceStaleness(type(uint24).max);
    }

    function __deployERC7540DepositQueue()
        internal
        returns (ERC7540LikeDepositQueueHarness depositQueue_, LimitedAccessLimitedCallForwarderHarness forwarder_)
    {
        depositQueue_ = new ERC7540LikeDepositQueueHarness(address(shares));
        vm.prank(admin);
        depositQueue_.setAsset(address(depositAsset));

        vm.prank(admin);
        shares.addDepositHandler(address(depositQueue_));

        // Deploy forwarder and set as admin on Shares
        forwarder_ = new LimitedAccessLimitedCallForwarderHarness(address(shares));
        vm.prank(owner);
        shares.addAdmin(address(forwarder_));

        // Whitelist calls on forwarder
        vm.startPrank(admin);
        forwarder_.addCall(address(depositQueue_), ERC7540LikeDepositQueue.executeDepositRequests.selector);
        forwarder_.addCall(address(walletsManager), WalletsManager.batchSendTokensViaCCIP.selector);
        vm.stopPrank();
    }

    //==================================================================================================================
    // Helpers
    //==================================================================================================================

    function __sendCCIPMessage(DepositorWallet.Call[] memory _calls, uint256 _depositAmount) internal {
        depositAsset.mintTo(user, _depositAmount);
        vm.prank(user);
        IERC20(address(depositAsset)).approve({spender: router, value: _depositAmount});

        address[] memory tokensToReturn = new address[](0);
        bytes memory messageData = abi.encode(_calls, tokensToReturn, "", address(0));

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(depositAsset), amount: _depositAmount});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(walletsManager)),
            data: messageData,
            tokenAmounts: tokenAmounts,
            feeToken: address(0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 2_000_000}))
        });

        vm.deal(user, ccipFee);
        vm.prank(user);
        IRouterClient(router).ccipSend{value: ccipFee}(chainSelector, message);
    }

    //==================================================================================================================
    // Tests: SyncDepositHandler
    //==================================================================================================================

    function test_syncDeposit() public {
        SyncDepositHandlerHarness depositHandler = __deploySyncDepositHandler();

        // Build calls: approve + deposit
        DepositorWallet.Call[] memory calls = new DepositorWallet.Call[](2);
        calls[0] = DepositorWallet.Call({
            target: address(depositAsset),
            data: abi.encodeWithSelector(IERC20.approve.selector, address(depositHandler), depositAmount),
            value: 0
        });
        calls[1] = DepositorWallet.Call({
            target: address(depositHandler),
            data: abi.encodeWithSelector(SyncDepositHandler.deposit.selector, depositAmount),
            value: 0
        });

        __sendCCIPMessage(calls, depositAmount);

        address wallet = walletsManager.computeWalletAddress(chainSelector, abi.encode(user));
        assertTrue(wallet != address(0), "wallet not deployed");
        assertEq(shares.balanceOf(wallet), expectedShares, "incorrect shares minted to wallet");
        assertEq(IERC20(address(depositAsset)).balanceOf(address(shares)), depositAmount, "deposit asset not in Shares");
        assertEq(IERC20(address(depositAsset)).balanceOf(user), 0, "user should have no remaining deposit asset");
    }

    //==================================================================================================================
    // Tests: ERC7540LikeDepositQueue
    //==================================================================================================================

    function test_erc7540DepositQueue_requestAndExecuteWithTokenReturn() public {
        (ERC7540LikeDepositQueueHarness depositQueue, LimitedAccessLimitedCallForwarderHarness forwarder) =
            __deployERC7540DepositQueue();

        address keeper = makeAddr("keeper");
        vm.prank(admin);
        forwarder.addUser(keeper);

        // Pre-compute wallet address
        address wallet = walletsManager.computeWalletAddress(chainSelector, abi.encode(user));

        // Phase 1: User sends CCIP message to request deposit
        DepositorWallet.Call[] memory calls = new DepositorWallet.Call[](2);
        calls[0] = DepositorWallet.Call({
            target: address(depositAsset),
            data: abi.encodeWithSelector(IERC20.approve.selector, address(depositQueue), depositAmount),
            value: 0
        });
        calls[1] = DepositorWallet.Call({
            target: address(depositQueue),
            data: abi.encodeWithSelector(
                ERC7540LikeDepositQueue.requestDeposit.selector, depositAmount, wallet, wallet
            ),
            value: 0
        });

        __sendCCIPMessage(calls, depositAmount);

        // Verify deposit request was created
        uint256 requestId = depositQueue.getDepositLastId();
        assertEq(requestId, 1, "request not created");
        ERC7540LikeDepositQueue.DepositRequestInfo memory request = depositQueue.getDepositRequest(requestId);
        assertEq(request.controller, wallet, "incorrect controller");
        assertEq(request.assetAmount, depositAmount, "incorrect asset amount");

        // Deposit asset held by queue, no shares minted yet
        assertEq(IERC20(address(depositAsset)).balanceOf(address(depositQueue)), depositAmount, "asset not in queue");
        assertEq(shares.balanceOf(wallet), 0, "shares should not be minted yet");

        // Phase 2: Keeper executes deposit + sends shares back to user via forwarder
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;

        address[] memory tokensToSend = new address[](1);
        tokensToSend[0] = address(shares);

        WalletsManager.BatchSendParams[] memory batchParams = new WalletsManager.BatchSendParams[](1);
        batchParams[0] = WalletsManager.BatchSendParams({wallet: wallet, tokens: tokensToSend, extraArgs: ""});

        OpenAccessLimitedCallForwarder.Call[] memory forwarderCalls = new OpenAccessLimitedCallForwarder.Call[](2);
        forwarderCalls[0] = OpenAccessLimitedCallForwarder.Call({
            target: address(depositQueue),
            data: abi.encodeWithSelector(ERC7540LikeDepositQueue.executeDepositRequests.selector, requestIds),
            value: 0
        });
        forwarderCalls[1] = OpenAccessLimitedCallForwarder.Call({
            target: address(walletsManager),
            data: abi.encodeWithSelector(WalletsManager.batchSendTokensViaCCIP.selector, batchParams),
            value: ccipFee
        });

        vm.deal(keeper, ccipFee);
        vm.prank(keeper);
        forwarder.executeCalls{value: ccipFee}(forwarderCalls);

        // Assert deposit asset transferred to Shares contract
        assertEq(IERC20(address(depositAsset)).balanceOf(address(shares)), depositAmount, "deposit asset not in Shares");
        assertEq(IERC20(address(depositAsset)).balanceOf(address(depositQueue)), 0, "queue should be empty");

        // Assert shares sent to user (via CCIP return)
        assertEq(shares.balanceOf(wallet), 0, "wallet should have no shares after return");
        assertEq(shares.balanceOf(user), expectedShares, "user should have received shares");

        // Assert native fee was consumed
        assertEq(keeper.balance, 0, "keeper should have spent all ETH on fee");
    }

    function test_erc7540DepositQueue_requestAndCancelWithWrappedNativeFee() public {
        (ERC7540LikeDepositQueueHarness depositQueue,) = __deployERC7540DepositQueue();

        // Pre-compute wallet address
        address wallet = walletsManager.computeWalletAddress(chainSelector, abi.encode(user));

        // Phase 1: User sends CCIP message to request deposit
        DepositorWallet.Call[] memory requestCalls = new DepositorWallet.Call[](2);
        requestCalls[0] = DepositorWallet.Call({
            target: address(depositAsset),
            data: abi.encodeWithSelector(IERC20.approve.selector, address(depositQueue), depositAmount),
            value: 0
        });
        requestCalls[1] = DepositorWallet.Call({
            target: address(depositQueue),
            data: abi.encodeWithSelector(
                ERC7540LikeDepositQueue.requestDeposit.selector, depositAmount, wallet, wallet
            ),
            value: 0
        });

        __sendCCIPMessage(requestCalls, depositAmount);

        uint256 requestId = depositQueue.getDepositLastId();
        assertEq(requestId, 1, "request not created");
        assertEq(IERC20(address(depositAsset)).balanceOf(address(depositQueue)), depositAmount, "asset not in queue");

        // Phase 2: User sends CCIP message to cancel deposit and get tokens back
        // User wraps ETH into WETH: send fee + tokens sent to wallet (excess returned alongside deposit asset)
        uint256 wethSent = ccipFee * 3;
        vm.deal(user, ccipFee + wethSent);
        vm.prank(user);
        WETH9(payable(wrappedNative)).deposit{value: ccipFee + wethSent}();
        vm.prank(user);
        IERC20(wrappedNative).approve({spender: router, value: ccipFee + wethSent});

        // Build cancel calls
        DepositorWallet.Call[] memory cancelCalls = new DepositorWallet.Call[](1);
        cancelCalls[0] = DepositorWallet.Call({
            target: address(depositQueue),
            data: abi.encodeWithSelector(ERC7540LikeDepositQueue.cancelDeposit.selector, requestId),
            value: 0
        });

        // Encode message data: cancel deposit, return both depositAsset and WETH, pay return fee in WETH
        address[] memory tokensToReturn = new address[](2);
        tokensToReturn[0] = address(depositAsset);
        tokensToReturn[1] = wrappedNative;
        bytes memory messageData = abi.encode(cancelCalls, tokensToReturn, "", wrappedNative);

        // Build CCIP message: send WETH to wallet, pay send fee in WETH
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: wrappedNative, amount: wethSent});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(walletsManager)),
            data: messageData,
            tokenAmounts: tokenAmounts,
            feeToken: wrappedNative,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 2_000_000}))
        });

        vm.prank(user);
        IRouterClient(router).ccipSend(chainSelector, message);

        // Assert deposit request was cancelled
        ERC7540LikeDepositQueue.DepositRequestInfo memory request = depositQueue.getDepositRequest(requestId);
        assertEq(request.controller, address(0), "request should be deleted");
        assertEq(IERC20(address(depositAsset)).balanceOf(address(depositQueue)), 0, "queue should be empty");

        // Assert deposit asset returned to user (via CCIP)
        assertEq(IERC20(address(depositAsset)).balanceOf(user), depositAmount, "user should have deposit asset back");
        assertEq(IERC20(address(depositAsset)).balanceOf(wallet), 0, "wallet should have no deposit asset");

        // Assert excess WETH returned to user: wethSent - returnFee (send fee paid separately from user's WETH)
        uint256 expectedWethReturned = wethSent - ccipFee;
        assertEq(IERC20(wrappedNative).balanceOf(user), expectedWethReturned, "user should have excess WETH back");
        assertEq(IERC20(wrappedNative).balanceOf(wallet), 0, "wallet should have no WETH remaining");
    }

    //==================================================================================================================
    // Tests: Failed call + token recovery
    //==================================================================================================================

    function test_syncDeposit_callFailsAndPullTokensBack() public {
        // Deploy SyncDepositHandler but do NOT register it on Shares — deposit will fail on mint
        SyncDepositHandlerHarness depositHandler = new SyncDepositHandlerHarness(address(shares));
        depositHandler.init(address(depositAsset));

        // Phase 1: User sends CCIP message with approve + deposit calls that will fail
        DepositorWallet.Call[] memory calls = new DepositorWallet.Call[](2);
        calls[0] = DepositorWallet.Call({
            target: address(depositAsset),
            data: abi.encodeWithSelector(IERC20.approve.selector, address(depositHandler), depositAmount),
            value: 0
        });
        calls[1] = DepositorWallet.Call({
            target: address(depositHandler),
            data: abi.encodeWithSelector(SyncDepositHandler.deposit.selector, depositAmount),
            value: 0
        });

        __sendCCIPMessage(calls, depositAmount);

        // Wallet deployed and holds the deposit asset; no shares minted
        address wallet = walletsManager.computeWalletAddress(chainSelector, abi.encode(user));
        assertTrue(wallet != address(0), "wallet not deployed");
        assertEq(IERC20(address(depositAsset)).balanceOf(wallet), depositAmount, "deposit asset should be in wallet");
        assertEq(shares.balanceOf(wallet), 0, "no shares should be minted");

        // Phase 2: User sends CCIP message to pull tokens back
        uint256 wethSent = ccipFee * 3;
        vm.deal(user, ccipFee + wethSent);
        vm.prank(user);
        WETH9(payable(wrappedNative)).deposit{value: ccipFee + wethSent}();
        vm.prank(user);
        IERC20(wrappedNative).approve({spender: router, value: ccipFee + wethSent});

        DepositorWallet.Call[] memory emptyCalls = new DepositorWallet.Call[](0);
        address[] memory tokensToReturn = new address[](2);
        tokensToReturn[0] = address(depositAsset);
        tokensToReturn[1] = wrappedNative;
        bytes memory messageData = abi.encode(emptyCalls, tokensToReturn, "", wrappedNative);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: wrappedNative, amount: wethSent});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(walletsManager)),
            data: messageData,
            tokenAmounts: tokenAmounts,
            feeToken: wrappedNative,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 2_000_000}))
        });

        vm.prank(user);
        IRouterClient(router).ccipSend(chainSelector, message);

        // Deposit asset returned to user
        assertEq(IERC20(address(depositAsset)).balanceOf(user), depositAmount, "user should have deposit asset back");
        assertEq(IERC20(address(depositAsset)).balanceOf(wallet), 0, "wallet should have no deposit asset");

        // Excess WETH returned to user: wethSent - returnFee
        uint256 expectedWethReturned = wethSent - ccipFee;
        assertEq(IERC20(wrappedNative).balanceOf(user), expectedWethReturned, "user should have excess WETH back");
        assertEq(IERC20(wrappedNative).balanceOf(wallet), 0, "wallet should have no WETH remaining");
    }
}
