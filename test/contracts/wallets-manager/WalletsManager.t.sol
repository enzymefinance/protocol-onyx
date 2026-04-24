// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test, Vm} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CCIPReceiver} from "@chainlink-ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink-ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink-ccip/interfaces/IRouterClient.sol";

import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {WalletsManager} from "src/components/ccip/WalletsManager.sol";
import {DepositorWallet} from "src/ccip/DepositorWallet.sol";
import {DeterministicBeaconFactory} from "src/factories/DeterministicBeaconFactory.sol";
import {Global} from "src/global/Global.sol";
import {Shares} from "src/shares/Shares.sol";

import {WalletsManagerHarness} from "test/harnesses/WalletsManagerHarness.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract WalletsManagerTest is TestHelpers {
    WalletsManagerHarness harness;
    Shares shares;
    DeterministicBeaconFactory factory;

    address owner;
    address admin = makeAddr("admin");
    address ccipRouter = makeAddr("ccipRouter");

    MockERC20 token1;
    MockERC20 token2;

    bytes user = abi.encode(makeAddr("user"));
    uint64 sourceChainSelector = 1;
    bytes32 mockMessageId = keccak256("mockMessageId");
    uint256 mockFee = 1e18;

    function setUp() public {
        // Deploy Shares and add admin
        shares = createShares();
        owner = shares.owner();
        vm.prank(owner);
        shares.addAdmin(admin);

        // Deploy Global, factory, and set DepositorWallet implementation
        Global global = new Global();
        global.init({_owner: address(this)});

        factory = new DeterministicBeaconFactory({_global: address(global)});
        DepositorWallet depositorWalletImpl = new DepositorWallet(ccipRouter);
        factory.setImplementation(address(depositorWalletImpl));

        // Deploy harness
        harness = new WalletsManagerHarness(address(shares), ccipRouter, address(factory));

        // Deploy mock tokens
        token1 = new MockERC20(18);
        token2 = new MockERC20(18);
    }

    //==================================================================================================================
    // Helpers
    //==================================================================================================================

    function __buildCCIPMessage(
        bytes32 _messageId,
        uint64 _sourceChainSelector,
        bytes memory _sender,
        bytes memory _data,
        Client.EVMTokenAmount[] memory _destTokenAmounts
    ) internal pure returns (Client.Any2EVMMessage memory) {
        return Client.Any2EVMMessage({
            messageId: _messageId,
            sourceChainSelector: _sourceChainSelector,
            sender: _sender,
            data: _data,
            destTokenAmounts: _destTokenAmounts
        });
    }

    function __deployWalletForUser(bytes memory _user, uint64 _chainSelector) internal returns (address wallet_) {
        Client.EVMTokenAmount[] memory emptyTokens = new Client.EVMTokenAmount[](0);
        Client.Any2EVMMessage memory message = __buildCCIPMessage({
            _messageId: keccak256("setup"),
            _sourceChainSelector: _chainSelector,
            _sender: _user,
            _data: "",
            _destTokenAmounts: emptyTokens
        });

        vm.prank(ccipRouter);
        harness.ccipReceive(message);

        wallet_ = harness.computeWalletAddress(_chainSelector, _user);
    }

    function __encodeProcessMessageData(
        DepositorWallet.Call[] memory _calls,
        address[] memory _tokensToReturn,
        bytes memory _extraArgs,
        address _feeTokenForReturn
    ) internal pure returns (bytes memory) {
        return abi.encode(_calls, _tokensToReturn, _extraArgs, _feeTokenForReturn);
    }

    function __hasLog(Vm.Log[] memory _logs, bytes32 _topic) internal pure returns (bool) {
        for (uint256 i; i < _logs.length; i++) {
            if (_logs[i].topics[0] == _topic) {
                return true;
            }
        }
        return false;
    }

    //==================================================================================================================
    // Tests
    //==================================================================================================================

    function test_WhenDeploying() external view {
        // It should set the CCIP router address.
        assertEq(harness.getRouter(), ccipRouter, "CCIP router not set");

        // It should set the DEPOSITOR_WALLETS_FACTORY.
        assertEq(address(harness.DEPOSITOR_WALLETS_FACTORY()), address(factory), "factory not set");
    }

    modifier whenCallingCcipReceive() {
        _;
    }

    function test_WhenTheCallerIsNotTheCCIPRouter() external whenCallingCcipReceive {
        // It should revert with {InvalidRouter}.
        address randomUser = makeAddr("randomUser");
        Client.EVMTokenAmount[] memory emptyTokens = new Client.EVMTokenAmount[](0);
        Client.Any2EVMMessage memory message = __buildCCIPMessage({
            _messageId: mockMessageId,
            _sourceChainSelector: sourceChainSelector,
            _sender: user,
            _data: "",
            _destTokenAmounts: emptyTokens
        });

        vm.expectRevert({
            revertData: abi.encodeWithSelector(CCIPReceiver.InvalidRouter.selector, randomUser),
            reverter: address(harness)
        });

        vm.prank(randomUser);
        harness.ccipReceive(message);
    }

    modifier whenTheCallerIsTheCCIPRouter() {
        _;
    }

    function test_GivenTheWalletAlreadyExistsForTheUser() external whenCallingCcipReceive whenTheCallerIsTheCCIPRouter {
        address existingWallet = __deployWalletForUser(user, sourceChainSelector);

        Client.EVMTokenAmount[] memory emptyTokens = new Client.EVMTokenAmount[](0);
        Client.Any2EVMMessage memory message = __buildCCIPMessage({
            _messageId: mockMessageId,
            _sourceChainSelector: sourceChainSelector,
            _sender: user,
            _data: "",
            _destTokenAmounts: emptyTokens
        });

        vm.prank(ccipRouter);
        harness.ccipReceive(message);

        // It should reuse the existing wallet.
        address walletAfter = harness.computeWalletAddress(sourceChainSelector, user);
        assertEq(walletAfter, existingWallet, "wallet should be reused");
    }

    modifier givenTheWalletDoesNotExistForTheUser() {
        _;
    }

    function test_GivenThePredictedAddressHasCode()
        external
        whenCallingCcipReceive
        whenTheCallerIsTheCCIPRouter
        givenTheWalletDoesNotExistForTheUser
    {
        // Compute predicted address and etch code at it
        address predicted = harness.computeWalletAddress(sourceChainSelector, user);
        vm.etch(predicted, hex"01");

        Client.EVMTokenAmount[] memory emptyTokens = new Client.EVMTokenAmount[](0);
        Client.Any2EVMMessage memory message = __buildCCIPMessage({
            _messageId: mockMessageId,
            _sourceChainSelector: sourceChainSelector,
            _sender: user,
            _data: "",
            _destTokenAmounts: emptyTokens
        });

        vm.prank(ccipRouter);
        harness.ccipReceive(message);

        // It should use the existing wallet at the predicted address.
        address resolved = harness.computeWalletAddress(sourceChainSelector, user);
        assertEq(resolved, predicted, "should use the predicted address");
    }

    function test_GivenThePredictedAddressHasNoCode()
        external
        whenCallingCcipReceive
        whenTheCallerIsTheCCIPRouter
        givenTheWalletDoesNotExistForTheUser
    {
        Client.EVMTokenAmount[] memory emptyTokens = new Client.EVMTokenAmount[](0);
        Client.Any2EVMMessage memory message = __buildCCIPMessage({
            _messageId: mockMessageId,
            _sourceChainSelector: sourceChainSelector,
            _sender: user,
            _data: "",
            _destTokenAmounts: emptyTokens
        });

        address predicted = harness.computeWalletAddress(sourceChainSelector, user);

        vm.prank(ccipRouter);
        harness.ccipReceive(message);

        // It should deploy a new wallet via the factory.
        address deployed = harness.computeWalletAddress(sourceChainSelector, user);
        assertEq(deployed, predicted, "deployed wallet should match predicted address");
        assertTrue(deployed.code.length > 0, "wallet should have code");
    }

    function test_WhenThereAreReceivedTokens() external whenCallingCcipReceive whenTheCallerIsTheCCIPRouter {
        uint256 amount1 = 100e18;
        uint256 amount2 = 200e18;

        // Mint tokens to harness (simulates router depositing)
        token1.mintTo(address(harness), amount1);
        token2.mintTo(address(harness), amount2);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](2);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(token1), amount: amount1});
        tokenAmounts[1] = Client.EVMTokenAmount({token: address(token2), amount: amount2});

        Client.Any2EVMMessage memory message = __buildCCIPMessage({
            _messageId: mockMessageId,
            _sourceChainSelector: sourceChainSelector,
            _sender: user,
            _data: "",
            _destTokenAmounts: tokenAmounts
        });

        vm.prank(ccipRouter);
        harness.ccipReceive(message);

        // It should transfer all received tokens to the wallet.
        address wallet = harness.computeWalletAddress(sourceChainSelector, user);
        assertEq(token1.balanceOf(wallet), amount1, "token1 not transferred to wallet");
        assertEq(token2.balanceOf(wallet), amount2, "token2 not transferred to wallet");
        assertEq(token1.balanceOf(address(harness)), 0, "token1 should not remain in harness");
        assertEq(token2.balanceOf(address(harness)), 0, "token2 should not remain in harness");
    }

    function test_WhenTheMessageHasNoData() external whenCallingCcipReceive whenTheCallerIsTheCCIPRouter {
        address wallet = __deployWalletForUser(user, sourceChainSelector);

        Client.EVMTokenAmount[] memory emptyTokens = new Client.EVMTokenAmount[](0);
        Client.Any2EVMMessage memory message = __buildCCIPMessage({
            _messageId: mockMessageId,
            _sourceChainSelector: sourceChainSelector,
            _sender: user,
            _data: "",
            _destTokenAmounts: emptyTokens
        });

        // It should emit a {CCIPMessageProcessed} event.
        vm.expectEmit(address(harness));
        emit WalletsManager.CCIPMessageProcessed({
            messageId: mockMessageId, sourceChainSelector: sourceChainSelector, wallet: wallet, message: message
        });

        // It should not call processMessageData.
        // (Verified implicitly: no processMessageData-related events/reverts)
        vm.prank(ccipRouter);
        harness.ccipReceive(message);
    }

    modifier whenTheMessageHasData() {
        _;
    }

    function test_WhenProcessMessageDataSucceeds()
        external
        whenCallingCcipReceive
        whenTheCallerIsTheCCIPRouter
        whenTheMessageHasData
    {
        address wallet = __deployWalletForUser(user, sourceChainSelector);

        // Build valid data with empty calls and no tokens to return
        DepositorWallet.Call[] memory calls = new DepositorWallet.Call[](0);
        address[] memory tokensToReturn = new address[](0);
        bytes memory data = __encodeProcessMessageData(calls, tokensToReturn, "", address(0));

        Client.EVMTokenAmount[] memory emptyTokens = new Client.EVMTokenAmount[](0);
        Client.Any2EVMMessage memory message = __buildCCIPMessage({
            _messageId: mockMessageId,
            _sourceChainSelector: sourceChainSelector,
            _sender: user,
            _data: data,
            _destTokenAmounts: emptyTokens
        });

        // It should emit a {CCIPMessageProcessed} event.
        vm.expectEmit(address(harness));
        emit WalletsManager.CCIPMessageProcessed({
            messageId: mockMessageId, sourceChainSelector: sourceChainSelector, wallet: wallet, message: message
        });

        vm.recordLogs();
        vm.prank(ccipRouter);
        harness.ccipReceive(message);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // It should not emit a {MessageDataProcessingFailed} event.
        assertFalse(
            __hasLog(logs, WalletsManager.MessageDataProcessingFailed.selector),
            "MessageDataProcessingFailed should not be emitted"
        );
    }

    function test_WhenProcessMessageDataFails()
        external
        whenCallingCcipReceive
        whenTheCallerIsTheCCIPRouter
        whenTheMessageHasData
    {
        uint256 tokenAmount = 100e18;

        address wallet = __deployWalletForUser(user, sourceChainSelector);
        token1.mintTo(address(harness), tokenAmount);

        // Build data with a call that will revert
        RevertingTarget revertingTarget = new RevertingTarget();
        DepositorWallet.Call[] memory calls = new DepositorWallet.Call[](1);
        calls[0] = DepositorWallet.Call({
            target: address(revertingTarget), data: abi.encodeWithSelector(RevertingTarget.doRevert.selector), value: 0
        });
        address[] memory tokensToReturn = new address[](0);
        bytes memory data = __encodeProcessMessageData(calls, tokensToReturn, "", address(0));

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(token1), amount: tokenAmount});

        Client.Any2EVMMessage memory message = __buildCCIPMessage({
            _messageId: mockMessageId,
            _sourceChainSelector: sourceChainSelector,
            _sender: user,
            _data: data,
            _destTokenAmounts: tokenAmounts
        });

        // It should emit a {MessageDataProcessingFailed} event with the revert reason.
        vm.expectEmit(address(harness));
        emit WalletsManager.MessageDataProcessingFailed({
            messageId: mockMessageId,
            wallet: wallet,
            reason: abi.encodeWithSelector(RevertingTarget.AlwaysReverts.selector)
        });

        // It should emit a {CCIPMessageProcessed} event.
        vm.expectEmit(address(harness));
        emit WalletsManager.CCIPMessageProcessed({
            messageId: mockMessageId, sourceChainSelector: sourceChainSelector, wallet: wallet, message: message
        });

        vm.prank(ccipRouter);
        harness.ccipReceive(message);

        // It should not revert the token transfers.
        assertEq(token1.balanceOf(wallet), tokenAmount, "tokens should still be in wallet");
    }

    modifier whenCallingProcessMessageData() {
        _;
    }

    function test_WhenTheCallerIsNotTheContractItself() external whenCallingProcessMessageData {
        // It should revert with {WalletsManager__ProcessMessageData__OnlySelfCallAllowed}.
        address randomUser = makeAddr("randomUser");

        vm.expectRevert({
            revertData: WalletsManager.WalletsManager__ProcessMessageData__OnlySelfCallAllowed.selector,
            reverter: address(harness)
        });

        vm.prank(randomUser);
        harness.processMessageData(address(0), "");
    }

    modifier whenTheCallerIsTheContractItself() {
        _;
    }

    function test_WhenThereAreNoCallsAndNoTokensToReturn()
        external
        whenCallingProcessMessageData
        whenTheCallerIsTheContractItself
    {
        address wallet = __deployWalletForUser(user, sourceChainSelector);

        DepositorWallet.Call[] memory calls = new DepositorWallet.Call[](0);
        address[] memory tokensToReturn = new address[](0);
        bytes memory data = __encodeProcessMessageData(calls, tokensToReturn, "", address(0));

        vm.recordLogs();
        vm.prank(address(harness));
        harness.processMessageData(wallet, data);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // It should not execute any calls on the wallet.
        assertFalse(__hasLog(logs, DepositorWallet.CallExecuted.selector), "CallExecuted should not be emitted");

        // It should not send a CCIP message.
        assertFalse(__hasLog(logs, DepositorWallet.CCIPMessageSent.selector), "CCIPMessageSent should not be emitted");
    }

    function test_WhenThereAreCalls() external whenCallingProcessMessageData whenTheCallerIsTheContractItself {
        address wallet = __deployWalletForUser(user, sourceChainSelector);

        CallTarget callTarget = new CallTarget();
        uint256 barValue = 42;
        bytes memory callData = abi.encodeWithSelector(CallTarget.setBar.selector, barValue);

        DepositorWallet.Call[] memory calls = new DepositorWallet.Call[](1);
        calls[0] = DepositorWallet.Call({target: address(callTarget), data: callData, value: 0});
        address[] memory tokensToReturn = new address[](0);
        bytes memory data = __encodeProcessMessageData(calls, tokensToReturn, "", address(0));

        // It should execute the calls on the wallet.
        vm.expectEmit(wallet);
        emit DepositorWallet.CallExecuted({target: address(callTarget), data: callData, value: 0});

        vm.prank(address(harness));
        harness.processMessageData(wallet, data);

        assertEq(callTarget.bar(), barValue, "call should have been executed");
    }

    function test_WhenThereAreNoTokensToReturn()
        external
        whenCallingProcessMessageData
        whenTheCallerIsTheContractItself
    {
        address wallet = __deployWalletForUser(user, sourceChainSelector);

        CallTarget callTarget = new CallTarget();
        DepositorWallet.Call[] memory calls = new DepositorWallet.Call[](1);
        calls[0] = DepositorWallet.Call({
            target: address(callTarget), data: abi.encodeWithSelector(CallTarget.setBar.selector, 1), value: 0
        });
        address[] memory tokensToReturn = new address[](0);
        bytes memory data = __encodeProcessMessageData(calls, tokensToReturn, "", address(0));

        vm.recordLogs();
        vm.prank(address(harness));
        harness.processMessageData(wallet, data);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // It should not send a CCIP message.
        assertFalse(__hasLog(logs, DepositorWallet.CCIPMessageSent.selector), "CCIPMessageSent should not be emitted");
    }

    function test_WhenThereAreTokensToReturn() external whenCallingProcessMessageData whenTheCallerIsTheContractItself {
        uint256 tokenBalance = 500e18;

        address wallet = __deployWalletForUser(user, sourceChainSelector);
        token1.mintTo(wallet, tokenBalance);

        // Mock router calls
        vm.mockCall(ccipRouter, abi.encodeWithSelector(IRouterClient.getFee.selector), abi.encode(mockFee));
        vm.mockCall(ccipRouter, abi.encodeWithSelector(IRouterClient.ccipSend.selector), abi.encode(mockMessageId));

        DepositorWallet.Call[] memory calls = new DepositorWallet.Call[](0);
        address[] memory tokensToReturn = new address[](1);
        tokensToReturn[0] = address(token1);
        bytes memory extraArgs = "";
        address feeTokenForReturn = address(token1);
        bytes memory data = __encodeProcessMessageData(calls, tokensToReturn, extraArgs, feeTokenForReturn);

        // It should build the return message via the wallet.
        // It should deduct the CCIP fee from the fee token amount.
        Client.EVMTokenAmount[] memory expectedTokenAmounts = new Client.EVMTokenAmount[](1);
        expectedTokenAmounts[0] = Client.EVMTokenAmount({token: address(token1), amount: tokenBalance - mockFee});

        Client.EVM2AnyMessage memory expectedMessage = Client.EVM2AnyMessage({
            receiver: user,
            data: "",
            tokenAmounts: expectedTokenAmounts,
            feeToken: feeTokenForReturn,
            extraArgs: extraArgs
        });

        // It should send the CCIP message via the wallet.
        vm.expectEmit(wallet);
        emit DepositorWallet.CCIPMessageSent({
            messageId: mockMessageId, chainSelector: sourceChainSelector, message: expectedMessage
        });

        vm.prank(address(harness));
        harness.processMessageData(wallet, data);
    }

    modifier whenCallingBatchSendTokensViaCCIP() {
        _;
    }

    function test_WhenTheCallerIsNotAnAdminOrOwner() external whenCallingBatchSendTokensViaCCIP {
        // It should revert with {ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized}.
        address randomUser = makeAddr("randomUser");
        WalletsManager.BatchSendParams[] memory params = new WalletsManager.BatchSendParams[](0);

        vm.expectRevert({
            revertData: ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector,
            reverter: address(harness)
        });

        vm.prank(randomUser);
        harness.batchSendTokensViaCCIP(params);
    }

    modifier whenTheCallerIsAnAdminOrOwner() {
        _;
    }

    function test_WhenTheCallerIsAnAdminOrOwner()
        external
        whenCallingBatchSendTokensViaCCIP
        whenTheCallerIsAnAdminOrOwner
    {
        uint256 tokenBalance = 300e18;

        address wallet = __deployWalletForUser(user, sourceChainSelector);
        token1.mintTo(wallet, tokenBalance);

        // Mock router calls
        vm.mockCall(ccipRouter, abi.encodeWithSelector(IRouterClient.getFee.selector), abi.encode(mockFee));
        vm.mockCall(ccipRouter, abi.encodeWithSelector(IRouterClient.ccipSend.selector), abi.encode(mockMessageId));

        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);

        WalletsManager.BatchSendParams[] memory params = new WalletsManager.BatchSendParams[](1);
        params[0] = WalletsManager.BatchSendParams({wallet: wallet, tokens: tokens, extraArgs: ""});

        // Build expected message (native fee token = address(0))
        Client.EVMTokenAmount[] memory expectedTokenAmounts = new Client.EVMTokenAmount[](1);
        expectedTokenAmounts[0] = Client.EVMTokenAmount({token: address(token1), amount: tokenBalance});

        Client.EVM2AnyMessage memory expectedMessage = Client.EVM2AnyMessage({
            receiver: user, data: "", tokenAmounts: expectedTokenAmounts, feeToken: address(0), extraArgs: ""
        });

        // It should build and send a return message for each wallet with native fee token.
        vm.expectEmit(wallet);
        emit DepositorWallet.CCIPMessageSent({
            messageId: mockMessageId, chainSelector: sourceChainSelector, message: expectedMessage
        });

        vm.deal(admin, mockFee);
        vm.prank(admin);
        harness.batchSendTokensViaCCIP{value: mockFee}(params);
    }

    function test_WhenThereIsRemainingETHBalance()
        external
        whenCallingBatchSendTokensViaCCIP
        whenTheCallerIsAnAdminOrOwner
    {
        uint256 tokenBalance = 300e18;
        uint256 sentValue = 5 ether;

        address wallet = __deployWalletForUser(user, sourceChainSelector);
        token1.mintTo(wallet, tokenBalance);

        vm.mockCall(ccipRouter, abi.encodeWithSelector(IRouterClient.getFee.selector), abi.encode(mockFee));
        vm.mockCall(ccipRouter, abi.encodeWithSelector(IRouterClient.ccipSend.selector), abi.encode(mockMessageId));

        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);

        WalletsManager.BatchSendParams[] memory params = new WalletsManager.BatchSendParams[](1);
        params[0] = WalletsManager.BatchSendParams({wallet: wallet, tokens: tokens, extraArgs: ""});

        vm.deal(admin, sentValue);
        uint256 adminBalanceBefore = admin.balance;

        vm.prank(admin);
        harness.batchSendTokensViaCCIP{value: sentValue}(params);

        // It should return the remaining ETH to the caller.
        uint256 expectedRemaining = sentValue - mockFee;
        assertEq(admin.balance, adminBalanceBefore - sentValue + expectedRemaining, "remaining ETH not returned");
        assertEq(address(harness).balance, 0, "harness should have no remaining ETH");
    }

    function test_WhenThereIsNoRemainingETHBalance()
        external
        whenCallingBatchSendTokensViaCCIP
        whenTheCallerIsAnAdminOrOwner
    {
        uint256 tokenBalance = 300e18;

        address wallet = __deployWalletForUser(user, sourceChainSelector);
        token1.mintTo(wallet, tokenBalance);

        vm.mockCall(ccipRouter, abi.encodeWithSelector(IRouterClient.getFee.selector), abi.encode(mockFee));
        vm.mockCall(ccipRouter, abi.encodeWithSelector(IRouterClient.ccipSend.selector), abi.encode(mockMessageId));

        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);

        WalletsManager.BatchSendParams[] memory params = new WalletsManager.BatchSendParams[](1);
        params[0] = WalletsManager.BatchSendParams({wallet: wallet, tokens: tokens, extraArgs: ""});

        // Send exactly the fee amount
        vm.deal(admin, mockFee);
        uint256 adminBalanceBefore = admin.balance;

        vm.prank(admin);
        harness.batchSendTokensViaCCIP{value: mockFee}(params);

        // It should not send ETH to the caller.
        assertEq(admin.balance, adminBalanceBefore - mockFee, "no extra ETH should be returned");
        assertEq(address(harness).balance, 0, "harness should have no remaining ETH");
    }

    function test_WhenCallingComputeWalletAddress() external {
        // It should return the deterministic wallet address.
        address predicted = harness.computeWalletAddress(sourceChainSelector, user);
        address deployed = __deployWalletForUser(user, sourceChainSelector);

        assertEq(predicted, deployed, "computed address should match deployed address");
    }
}

contract CallTarget {
    uint256 public bar;

    function setBar(uint256 _bar) external payable {
        bar = _bar;
    }
}

contract RevertingTarget {
    error AlwaysReverts();

    function doRevert() external pure {
        revert AlwaysReverts();
    }
}
