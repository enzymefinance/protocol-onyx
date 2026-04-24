// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Client} from "@chainlink-ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink-ccip/interfaces/IRouterClient.sol";

import {DepositorWallet} from "src/ccip/DepositorWallet.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";

contract DepositorWalletTest is Test {
    DepositorWallet wallet;

    address ccipRouter = makeAddr("ccipRouter");
    address walletsManager = makeAddr("walletsManager");
    bytes user = abi.encode(makeAddr("user"));
    uint64 chainSelector = 1;

    MockERC20 token1;
    MockERC20 token2;
    MockERC20 feeToken;

    bytes32 mockMessageId = keccak256("mockMessageId");

    function setUp() public {
        wallet = new DepositorWallet(ccipRouter);
        wallet.init({_walletsManager: walletsManager, _user: user, _chainSelector: chainSelector});

        token1 = new MockERC20(18);
        token2 = new MockERC20(18);
        feeToken = new MockERC20(18);
    }

    function test_WhenDeploying() external view {
        // It should set the CCIP router address.
        assertEq(wallet.CCIP_ROUTER(), ccipRouter, "CCIP router not set");
    }

    modifier whenCallingInit() {
        _;
    }

    function test_RevertGiven_ItHasAlreadyBeenInitialized() external whenCallingInit {
        // It should revert.
        vm.expectRevert({revertData: Initializable.InvalidInitialization.selector, reverter: address(wallet)});
        wallet.init({_walletsManager: walletsManager, _user: user, _chainSelector: chainSelector});
    }

    function test_GivenItHasNotBeenInitialized() external whenCallingInit {
        DepositorWallet freshWallet = new DepositorWallet(ccipRouter);

        // It should emit a {WalletsManagerSet} event.
        vm.expectEmit(address(freshWallet));
        emit DepositorWallet.WalletsManagerSet(walletsManager);

        // It should emit a {UserSet} event.
        vm.expectEmit(address(freshWallet));
        emit DepositorWallet.UserSet(user);

        // It should emit a {ChainSelectorSet} event.
        vm.expectEmit(address(freshWallet));
        emit DepositorWallet.ChainSelectorSet(chainSelector);

        freshWallet.init({_walletsManager: walletsManager, _user: user, _chainSelector: chainSelector});

        // It should set the wallets manager.
        assertEq(freshWallet.getWalletsManager(), walletsManager, "wallets manager not set");

        // It should set the user.
        assertEq(freshWallet.getUser(), user, "user not set");

        // It should set the chain selector.
        assertEq(freshWallet.getChainSelector(), chainSelector, "chain selector not set");
    }

    modifier whenCallingSendCCIPMessage() {
        vm.mockCall(ccipRouter, abi.encodeWithSelector(IRouterClient.ccipSend.selector), abi.encode(mockMessageId));
        _;
    }

    function test_WhenTheCallerIsNotTheWalletsManager() external whenCallingSendCCIPMessage {
        // It should revert with {DepositorWallet__OnlyWalletsManager__Unauthorized}.
        address randomUser = makeAddr("randomUser");
        Client.EVM2AnyMessage memory message;

        vm.expectRevert({
            revertData: DepositorWallet.DepositorWallet__OnlyWalletsManager__Unauthorized.selector,
            reverter: address(wallet)
        });

        vm.prank(randomUser);
        wallet.sendCCIPMessage(message, 0);
    }

    modifier whenTheCallerIsTheWalletsManager() {
        vm.startPrank(walletsManager);
        _;
        vm.stopPrank();
    }

    function test_WhenTheCallerIsTheWalletsManager()
        external
        whenCallingSendCCIPMessage
        whenTheCallerIsTheWalletsManager
    {
        // It should approve the tokens for the CCIP router.
        uint256 amount1 = 100e18;
        uint256 amount2 = 200e18;

        token1.mintTo(address(wallet), amount1);
        token2.mintTo(address(wallet), amount2);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](2);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(token1), amount: amount1});
        tokenAmounts[1] = Client.EVMTokenAmount({token: address(token2), amount: amount2});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: user, data: "", tokenAmounts: tokenAmounts, feeToken: address(0), extraArgs: ""
        });

        wallet.sendCCIPMessage(message, 0);

        assertEq(IERC20(address(token1)).allowance(address(wallet), ccipRouter), amount1, "token1 allowance mismatch");
        assertEq(IERC20(address(token2)).allowance(address(wallet), ccipRouter), amount2, "token2 allowance mismatch");
    }

    function test_WhenTheFeeTokenIsTheNativeCurrency()
        external
        whenCallingSendCCIPMessage
        whenTheCallerIsTheWalletsManager
    {
        uint256 amount1 = 100e18;
        token1.mintTo(address(wallet), amount1);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(token1), amount: amount1});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: user, data: "", tokenAmounts: tokenAmounts, feeToken: address(0), extraArgs: ""
        });

        uint256 feeValue = 0.1 ether;

        // It should emit a {CCIPMessageSent} event.
        vm.expectEmit(address(wallet));
        emit DepositorWallet.CCIPMessageSent({messageId: mockMessageId, chainSelector: chainSelector, message: message});

        // It should send the CCIP message with native fee value.
        vm.deal(walletsManager, feeValue);
        wallet.sendCCIPMessage{value: feeValue}(message, feeValue);
    }

    function test_WhenTheFeeTokenIsAnERC20Token() external whenCallingSendCCIPMessage whenTheCallerIsTheWalletsManager {
        uint256 amount1 = 100e18;
        token1.mintTo(address(wallet), amount1);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(token1), amount: amount1});

        uint256 feeValue = 50e18;

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: user, data: "", tokenAmounts: tokenAmounts, feeToken: address(feeToken), extraArgs: ""
        });

        // It should emit a {CCIPMessageSent} event.
        vm.expectEmit(address(wallet));
        emit DepositorWallet.CCIPMessageSent({messageId: mockMessageId, chainSelector: chainSelector, message: message});

        wallet.sendCCIPMessage(message, feeValue);

        // It should approve the fee token for the CCIP router.
        assertEq(
            IERC20(address(feeToken)).allowance(address(wallet), ccipRouter), feeValue, "fee token allowance mismatch"
        );

        // It should send the CCIP message without native fee value.
        // Verified implicitly: the function sends value 0 when feeToken != address(0).
    }

    function test_WhenCallingBuildTokenReturnMessage() external {
        uint256 balance1 = 500e18;
        uint256 balance2 = 300e18;
        token1.mintTo(address(wallet), balance1);
        token2.mintTo(address(wallet), balance2);

        bytes memory extraArgs = bytes("extraArgs");
        uint256 mockFee = 1e18;

        vm.mockCall(ccipRouter, abi.encodeWithSelector(IRouterClient.getFee.selector), abi.encode(mockFee));

        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);

        (Client.EVM2AnyMessage memory message, uint256 fee) =
            wallet.buildTokenReturnMessage(tokens, extraArgs, address(feeToken));

        // It should set the receiver to the user.
        assertEq(message.receiver, user, "receiver mismatch");

        // It should set the data to empty.
        assertEq(message.data, "", "data should be empty");

        // It should set the token amounts with the current balances.
        assertEq(message.tokenAmounts.length, 2, "token amounts length mismatch");
        assertEq(message.tokenAmounts[0].token, address(token1), "token1 address mismatch");
        assertEq(message.tokenAmounts[0].amount, balance1, "token1 balance mismatch");
        assertEq(message.tokenAmounts[1].token, address(token2), "token2 address mismatch");
        assertEq(message.tokenAmounts[1].amount, balance2, "token2 balance mismatch");

        // It should set the fee token.
        assertEq(message.feeToken, address(feeToken), "fee token mismatch");

        // It should return the CCIP fee.
        assertEq(fee, mockFee, "fee mismatch");
    }

    modifier whenCallingExecuteCalls() {
        _;
    }

    function test_WhenTheCallerIsNotTheWalletsManager_WhenCallingExecuteCalls() external whenCallingExecuteCalls {
        // It should revert with {DepositorWallet__OnlyWalletsManager__Unauthorized}.
        address randomUser = makeAddr("randomUser");
        DepositorWallet.Call[] memory calls = new DepositorWallet.Call[](0);

        vm.expectRevert({
            revertData: DepositorWallet.DepositorWallet__OnlyWalletsManager__Unauthorized.selector,
            reverter: address(wallet)
        });

        vm.prank(randomUser);
        wallet.executeCalls(calls);
    }

    function test_RevertWhen_ACallFails() external whenCallingExecuteCalls whenTheCallerIsTheWalletsManager {
        // It should revert.
        RevertingTarget revertingTarget = new RevertingTarget();

        DepositorWallet.Call[] memory calls = new DepositorWallet.Call[](1);
        calls[0] = DepositorWallet.Call({
            target: address(revertingTarget), data: abi.encodeWithSelector(RevertingTarget.doRevert.selector), value: 0
        });

        vm.expectRevert({revertData: RevertingTarget.AlwaysReverts.selector, reverter: address(revertingTarget)});

        wallet.executeCalls(calls);
    }

    function test_WhenAllCallsSucceed() external whenCallingExecuteCalls whenTheCallerIsTheWalletsManager {
        CallTarget callTarget1 = new CallTarget();
        CallTarget callTarget2 = new CallTarget();

        uint256 bar1 = 123;
        uint256 bar2 = 456;
        bytes memory callData1 = abi.encodeWithSelector(CallTarget.setBar.selector, bar1);
        bytes memory callData2 = abi.encodeWithSelector(CallTarget.setBar.selector, bar2);
        uint256 value1 = 100;
        uint256 value2 = 300;

        vm.deal(address(wallet), value1 + value2);

        DepositorWallet.Call[] memory calls = new DepositorWallet.Call[](2);
        calls[0] = DepositorWallet.Call({target: address(callTarget1), data: callData1, value: value1});
        calls[1] = DepositorWallet.Call({target: address(callTarget2), data: callData2, value: value2});

        // It should emit a {CallExecuted} event for each call.
        vm.expectEmit(address(wallet));
        emit DepositorWallet.CallExecuted({target: address(callTarget1), data: callData1, value: value1});

        vm.expectEmit(address(wallet));
        emit DepositorWallet.CallExecuted({target: address(callTarget2), data: callData2, value: value2});

        wallet.executeCalls(calls);

        // It should execute all calls.
        assertEq(callTarget1.bar(), bar1, "callTarget1 bar mismatch");
        assertEq(callTarget2.bar(), bar2, "callTarget2 bar mismatch");
        assertEq(address(callTarget1).balance, value1, "callTarget1 balance mismatch");
        assertEq(address(callTarget2).balance, value2, "callTarget2 balance mismatch");
    }

    function test_WhenReceivingNativeCurrency() external {
        // It should accept native currency.
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);

        (bool success,) = address(wallet).call{value: amount}("");
        assertTrue(success, "should accept native currency");
        assertEq(address(wallet).balance, amount, "balance mismatch");
    }

    function test_WhenCallingGetWalletsManager() external view {
        // It should return the wallets manager address.
        assertEq(wallet.getWalletsManager(), walletsManager, "wallets manager mismatch");
    }

    function test_WhenCallingGetUser() external view {
        // It should return the user.
        assertEq(wallet.getUser(), user, "user mismatch");
    }

    function test_WhenCallingGetChainSelector() external view {
        // It should return the chain selector.
        assertEq(wallet.getChainSelector(), chainSelector, "chain selector mismatch");
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
