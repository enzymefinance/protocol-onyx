// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ERC7540LikeRedeemQueue} from "src/components/issuance/redeem-handlers/ERC7540LikeRedeemQueue.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {IERC7540LikeRedeemHandler} from "src/components/issuance/redeem-handlers/IERC7540LikeRedeemHandler.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {Shares} from "src/shares/Shares.sol";

import {ERC7540LikeRedeemQueueHarness} from "test/harnesses/ERC7540LikeRedeemQueueHarness.sol";
import {ValuationHandlerHarness} from "test/harnesses/ValuationHandlerHarness.sol";
import {MockChainlinkAggregator} from "test/mocks/MockChainlinkAggregator.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract ERC7540LikeRedeemQueueTest is TestHelpers {
    Shares shares;
    address owner;
    address admin = makeAddr("admin");
    ValuationHandler valuationHandler;

    ERC7540LikeRedeemQueueHarness redeemQueue;

    struct ExecuteRedeemSetupData {
        address asset;
        address request1Controller;
        address request3Controller;
        uint256 request1SharesAmount;
        uint256 request3SharesAmount;
        uint256 request1ExpectedAssetAmount;
        uint256 request3ExpectedAssetAmount;
    }

    function setUp() public {
        shares = createShares();
        owner = shares.owner();

        vm.prank(owner);
        shares.addAdmin(admin);

        // Deploy harness contract and set it on Shares
        redeemQueue = new ERC7540LikeRedeemQueueHarness(address(shares));
        vm.prank(admin);
        shares.addRedeemHandler(address(redeemQueue));

        // Create a mock ValuationHandler and set it on Shares
        valuationHandler = ValuationHandler(address(new ValuationHandlerHarness(address(shares))));
        vm.prank(admin);
        shares.setValuationHandler(address(valuationHandler));
    }

    //==================================================================================================================
    // Config (access: admin or owner)
    //==================================================================================================================

    function test_setRedeemMinRequestDuration_fail_notAdminOrOwner() public {
        address randomUser = makeAddr("randomUser");
        uint24 minRequestDuration = 123;

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        redeemQueue.setRedeemMinRequestDuration(minRequestDuration);
    }

    function test_setRedeemMinRequestDuration_success() public {
        uint24 minRequestDuration = 123;

        vm.expectEmit();
        emit ERC7540LikeRedeemQueue.RedeemMinRequestDurationSet(minRequestDuration);

        vm.prank(admin);
        redeemQueue.setRedeemMinRequestDuration(minRequestDuration);

        assertEq(redeemQueue.getRedeemMinRequestDuration(), minRequestDuration);
    }

    //==================================================================================================================
    // Required: IERC7540LikeRedeemHandler
    //==================================================================================================================

    function test_cancelRedeem_fail_notRequestOwner() public {
        uint256 requestId = __test_cancelRedeem_setup();

        address randomUser = makeAddr("randomUser");
        vm.expectRevert(ERC7540LikeRedeemQueue.ERC7540LikeRedeemQueue__CancelRequest__Unauthorized.selector);
        vm.prank(randomUser);
        redeemQueue.cancelRedeem(requestId);
    }

    function test_cancelRedeem_fail_minRequestDurationNotElapsed() public {
        uint256 requestId = __test_cancelRedeem_setup();
        address controller = redeemQueue.getRedeemRequest(requestId).controller;

        vm.expectRevert(
            ERC7540LikeRedeemQueue.ERC7540LikeRedeemQueue__CancelRequest__MinRequestDurationNotElapsed.selector
        );
        vm.prank(controller);
        redeemQueue.cancelRedeem(requestId);
    }

    function test_cancelRedeem_success() public {
        uint256 requestId = __test_cancelRedeem_setup();

        // cancelable condition
        vm.warp(block.timestamp + redeemQueue.getRedeemMinRequestDuration());

        __test_cancelRedeem_success({_requestId: requestId});
    }

    function __test_cancelRedeem_setup() internal returns (uint256 requestId_) {
        // Define a controller, and seed it with shares, and grant allowance to the redeem queue
        address controller = makeAddr("controller");
        deal(address(shares), controller, 1000 * 10 ** shares.decimals(), true);
        vm.prank(controller);
        shares.approve(address(redeemQueue), type(uint256).max);

        // Set a min request time
        vm.prank(admin);
        redeemQueue.setRedeemMinRequestDuration(11);

        // Warp to an arbitrary time for the request
        uint256 requestTime = 123456;
        vm.warp(requestTime);

        // Create a request
        vm.prank(controller);
        return redeemQueue.requestRedeem({_shares: 123, _controller: controller, _owner: controller});
    }

    function __test_cancelRedeem_success(uint256 _requestId) internal {
        address controller = redeemQueue.getRedeemRequest(_requestId).controller;
        uint256 redeemSharesAmount = redeemQueue.getRedeemRequest(_requestId).sharesAmount;

        uint256 preControllerBalance = shares.balanceOf(controller);
        uint256 preSupply = shares.totalSupply();

        vm.expectEmit();
        emit IERC7540LikeRedeemHandler.RedeemRequestCanceled(_requestId);

        vm.prank(controller);
        uint256 sharesAmountRefunded = redeemQueue.cancelRedeem(_requestId);

        // Shares should be refunded
        assertEq(sharesAmountRefunded, redeemSharesAmount);
        assertEq(shares.balanceOf(controller), preControllerBalance + redeemSharesAmount);

        // Shares supply should be the same
        assertEq(shares.totalSupply(), preSupply);

        // Request should be zeroed out
        assertEq(redeemQueue.getRedeemRequest(_requestId).controller, address(0));
    }

    function test_requestRedeem_fail_ownerNotSender() public {
        address sender = makeAddr("sender");
        address controller = makeAddr("controller");
        address sharesOwner = controller;
        uint256 redeemSharesAmount = 123;
        __test_requestRedeem_setup({_sharesOwner: sharesOwner});

        vm.expectRevert(ERC7540LikeRedeemQueue.ERC7540LikeRedeemQueue__RequestRedeem__OwnerNotSender.selector);
        vm.prank(sender);
        redeemQueue.requestRedeem({_shares: redeemSharesAmount, _controller: controller, _owner: sharesOwner});
    }

    function test_requestRedeem_fail_ownerNotController() public {
        address controller = makeAddr("controller");
        address sharesOwner = makeAddr("sharesOwner");
        uint256 redeemSharesAmount = 123;
        __test_requestRedeem_setup({_sharesOwner: sharesOwner});

        vm.expectRevert(ERC7540LikeRedeemQueue.ERC7540LikeRedeemQueue__RequestRedeem__OwnerNotController.selector);
        vm.prank(sharesOwner);
        redeemQueue.requestRedeem({_shares: redeemSharesAmount, _controller: controller, _owner: sharesOwner});
    }

    function test_requestRedeem_fail_zeroShares() public {
        address controller = makeAddr("controller");
        address sharesOwner = controller;
        __test_requestRedeem_setup({_sharesOwner: sharesOwner});

        vm.expectRevert(ERC7540LikeRedeemQueue.ERC7540LikeRedeemQueue__RequestRedeem__ZeroShares.selector);
        vm.prank(sharesOwner);
        redeemQueue.requestRedeem({_shares: 0, _controller: controller, _owner: sharesOwner});
    }

    function test_requestRedeem_success() public {
        address controller = makeAddr("controller");
        address sharesOwner = controller;
        __test_requestRedeem_setup({_sharesOwner: sharesOwner});

        __test_requestRedeem_success({_controller: controller, _sharesOwner: sharesOwner, _sharesAmount: 123});
    }

    function __test_requestRedeem_success(address _controller, address _sharesOwner, uint256 _sharesAmount) internal {
        uint256 expectedRequestId = redeemQueue.getRedeemLastId() + 1;
        uint256 expectedCanCancelTime = block.timestamp + redeemQueue.getRedeemMinRequestDuration();

        uint256 preRequestQueueSharesBalance = shares.balanceOf(address(redeemQueue));
        uint256 preRequestSharesOwnerSharesBalance = shares.balanceOf(_sharesOwner);

        vm.expectEmit();
        emit IERC7540LikeRedeemHandler.RedeemRequest({
            controller: _controller,
            owner: _sharesOwner,
            requestId: expectedRequestId,
            sender: _sharesOwner,
            shares: _sharesAmount
        });

        vm.prank(_sharesOwner);
        redeemQueue.requestRedeem({_shares: _sharesAmount, _controller: _controller, _owner: _sharesOwner});

        // Assert request storage
        ERC7540LikeRedeemQueue.RedeemRequestInfo memory request = redeemQueue.getRedeemRequest(expectedRequestId);
        assertEq(request.controller, _controller);
        assertEq(request.sharesAmount, _sharesAmount);
        assertEq(request.canCancelTime, expectedCanCancelTime);

        // Assert shares transfer
        assertEq(shares.balanceOf(address(redeemQueue)), preRequestQueueSharesBalance + _sharesAmount);
        assertEq(shares.balanceOf(_sharesOwner), preRequestSharesOwnerSharesBalance - _sharesAmount);
    }

    function __test_requestRedeem_setup(address _sharesOwner) internal {
        // Seed shares owner with shares, and grant allowance to the queue
        deal(address(shares), _sharesOwner, 1000 * 10 ** shares.decimals(), true);
        vm.prank(_sharesOwner);
        shares.approve(address(redeemQueue), type(uint256).max);

        // Set a min request time
        vm.prank(admin);
        redeemQueue.setRedeemMinRequestDuration(11);

        // Warp to an arbitrary time for the request
        uint256 requestTime = 123456;
        vm.warp(requestTime);
    }

    //==================================================================================================================
    // Request fulfillment
    //==================================================================================================================

    function test_executeRedeemRequests_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);
        vm.prank(randomUser);
        redeemQueue.executeRedeemRequests({_requestIds: new uint256[](0)});
    }

    // Queues 3 requests, and executes 2 of them
    function __test_executeRedeemRequests_setup() private returns (ExecuteRedeemSetupData memory data_) {
        // Define requests
        data_.request1Controller = makeAddr("controller1");
        address request2Controller = makeAddr("controller2");
        data_.request3Controller = makeAddr("controller3");

        data_.request1SharesAmount = 20e18; // 20 shares
        data_.request3SharesAmount = 40e18; // 40 shares

        uint256 request1FeeSharesAmount = 2e18; // 10% fee
        uint256 request3FeeSharesAmount = 4e18; // 10% fee

        uint128 redeemAssetToValueAssetRate = 4e18; // 4:1 conversion rate (4 value units per 1 asset unit)
        // sharePrice = 1e18; // Keep it simple with 1:1 share price

        data_.request1ExpectedAssetAmount = 4.5e6; // (20 shares - 10% fee)/4 = 4.5 asset units
        data_.request3ExpectedAssetAmount = 9e6; // (40 shares - 10% fee)/4 = 9 asset units

        // Create and set the asset
        uint8 assetDecimals = 6;
        data_.asset = address(new MockERC20(assetDecimals));
        vm.prank(admin);
        redeemQueue.setAsset({_asset: data_.asset});

        // Set the asset rate
        vm.prank(admin);
        valuationHandler.setAssetRate(
            ValuationHandler.AssetRateInput({
                asset: data_.asset, rate: redeemAssetToValueAssetRate, expiry: uint40(block.timestamp + 1)
            })
        );

        // Mock and set a fee handler with different fee amounts for each request shares amount
        address mockFeeHandler = makeAddr("mockFeeHandler");
        feeHandler_mockSettleExitFeeGivenGrossShares({
            _feeHandler: mockFeeHandler,
            _feeSharesAmount: request1FeeSharesAmount,
            _grossSharesAmount: data_.request1SharesAmount
        });
        feeHandler_mockSettleExitFeeGivenGrossShares({
            _feeHandler: mockFeeHandler,
            _feeSharesAmount: request3FeeSharesAmount,
            _grossSharesAmount: data_.request3SharesAmount
        });

        vm.prank(admin);
        shares.setFeeHandler(mockFeeHandler);

        // Seed Shares with the asset
        deal(data_.asset, address(shares), 1000 * 10 ** IERC20(data_.asset).decimals(), true);

        // Seed controllers with shares, and grant allowance to the queue
        address[3] memory controllers = [data_.request1Controller, request2Controller, data_.request3Controller];
        for (uint256 i; i < controllers.length; i++) {
            deal(address(shares), controllers[i], 1000 * 10 ** shares.decimals(), true);
            vm.prank(controllers[i]);
            shares.approve(address(redeemQueue), type(uint256).max);
        }

        // Create the requests
        vm.prank(data_.request1Controller);
        redeemQueue.requestRedeem({
            _shares: data_.request1SharesAmount, _controller: data_.request1Controller, _owner: data_.request1Controller
        });
        vm.prank(request2Controller);
        redeemQueue.requestRedeem({_shares: 456, _controller: request2Controller, _owner: request2Controller});
        vm.prank(data_.request3Controller);
        redeemQueue.requestRedeem({
            _shares: data_.request3SharesAmount, _controller: data_.request3Controller, _owner: data_.request3Controller
        });
    }

    function test_executeRedeemRequests_success() public {
        ExecuteRedeemSetupData memory d = __test_executeRedeemRequests_setup();

        // Define ids to execute: first and last items
        uint256[] memory requestIdsToExecute = new uint256[](2);
        requestIdsToExecute[0] = 1;
        requestIdsToExecute[1] = 3;

        uint256 preExecuteTotalSupply = shares.totalSupply();

        // Pre-assert events
        vm.expectEmit();
        emit IERC7540LikeRedeemHandler.Withdraw({
            sender: admin,
            receiver: d.request1Controller,
            owner: d.request1Controller,
            assets: d.request1ExpectedAssetAmount,
            shares: d.request1SharesAmount
        });
        vm.expectEmit();
        emit IERC7540LikeRedeemHandler.RedeemRequestExecuted({requestId: 1, assetAmount: d.request1ExpectedAssetAmount});

        vm.expectEmit();
        emit IERC7540LikeRedeemHandler.Withdraw({
            sender: admin,
            receiver: d.request3Controller,
            owner: d.request3Controller,
            assets: d.request3ExpectedAssetAmount,
            shares: d.request3SharesAmount
        });
        vm.expectEmit();
        emit IERC7540LikeRedeemHandler.RedeemRequestExecuted({requestId: 3, assetAmount: d.request3ExpectedAssetAmount});

        // Execute the requests
        vm.prank(admin);
        redeemQueue.executeRedeemRequests({_requestIds: requestIdsToExecute});

        // Assert assets sent
        assertEq(IERC20(d.asset).balanceOf(d.request1Controller), d.request1ExpectedAssetAmount);
        assertEq(IERC20(d.asset).balanceOf(d.request3Controller), d.request3ExpectedAssetAmount);

        // Assert shares are burned
        assertEq(shares.totalSupply(), preExecuteTotalSupply - (d.request1SharesAmount + d.request3SharesAmount));

        // Assert requests are removed
        assertEq(redeemQueue.getRedeemRequest(1).controller, address(0));
        assertEq(redeemQueue.getRedeemRequest(3).controller, address(0));
    }
}
