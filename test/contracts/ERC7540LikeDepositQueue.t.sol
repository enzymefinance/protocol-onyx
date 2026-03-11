// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ERC7540LikeDepositQueue} from "src/components/issuance/deposit-handlers/ERC7540LikeDepositQueue.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {IERC7540LikeDepositHandler} from "src/components/issuance/deposit-handlers/IERC7540LikeDepositHandler.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {Shares} from "src/shares/Shares.sol";

import {ERC7540LikeDepositQueueHarness} from "test/harnesses/ERC7540LikeDepositQueueHarness.sol";
import {ValuationHandlerHarness} from "test/harnesses/ValuationHandlerHarness.sol";
import {BlankAddressList} from "test/mocks/Blanks.sol";
import {MockChainlinkAggregator} from "test/mocks/MockChainlinkAggregator.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract ERC7540LikeDepositQueueTest is TestHelpers {
    Shares shares;
    address owner;
    address admin = makeAddr("admin");
    ValuationHandler valuationHandler;

    ERC7540LikeDepositQueueHarness depositQueue;

    struct ExecuteDepositSetupData {
        address asset;
        address request1Controller;
        address request3Controller;
        uint256 request1AssetAmount;
        uint256 request3AssetAmount;
        uint256 request1ExpectedSharesAmount;
        uint256 request3ExpectedSharesAmount;
    }

    function setUp() public {
        shares = createShares();
        owner = shares.owner();

        vm.prank(owner);
        shares.addAdmin(admin);

        // Deploy harness contract and set it on Shares
        depositQueue = new ERC7540LikeDepositQueueHarness(address(shares));
        vm.prank(admin);
        shares.addDepositHandler(address(depositQueue));

        // Create a mock ValuationHandler and set it on Shares
        valuationHandler = ValuationHandler(address(new ValuationHandlerHarness(address(shares))));
        vm.prank(admin);
        shares.setValuationHandler(address(valuationHandler));
    }

    //==================================================================================================================
    // Config (access: admin or owner)
    //==================================================================================================================

    function test_addDepositControllerToInternalAllowlist_fail_notAdminOrOwner() public {
        address randomUser = makeAddr("randomUser");
        address controller = makeAddr("controller");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        depositQueue.addDepositControllerToInternalAllowlist(controller);
    }

    function test_addDepositControllerToInternalAllowlist_success() public {
        address controller = makeAddr("controller");

        vm.expectEmit(address(depositQueue));
        emit ERC7540LikeDepositQueue.AllowedControllerAdded({controller: controller});

        vm.prank(admin);
        depositQueue.addDepositControllerToInternalAllowlist(controller);

        assertTrue(depositQueue.isInDepositControllerInternalAllowlist(controller), "controller not in list");
    }

    function test_removeDepositControllerFromInternalAllowlist_fail_notAdminOrOwner() public {
        address randomUser = makeAddr("randomUser");
        address controller = makeAddr("controller");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        depositQueue.removeDepositControllerFromInternalAllowlist(controller);
    }

    function test_removeDepositControllerFromInternalAllowlist_success() public {
        address controller = makeAddr("controller");

        vm.prank(admin);
        depositQueue.addDepositControllerToInternalAllowlist(controller);

        assertTrue(depositQueue.isInDepositControllerInternalAllowlist(controller), "controller not in list");

        vm.expectEmit(address(depositQueue));
        emit ERC7540LikeDepositQueue.AllowedControllerRemoved({controller: controller});

        vm.prank(admin);
        depositQueue.removeDepositControllerFromInternalAllowlist(controller);

        assertFalse(depositQueue.isInDepositControllerInternalAllowlist(controller), "controller still in list");
    }

    function test_setDepositMinRequestDuration_fail_notAdminOrOwner() public {
        address randomUser = makeAddr("randomUser");
        uint24 minRequestDuration = 123;

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        depositQueue.setDepositMinRequestDuration(minRequestDuration);
    }

    function test_setDepositMinRequestDuration_success() public {
        uint24 minRequestDuration = 123;

        vm.expectEmit(address(depositQueue));
        emit ERC7540LikeDepositQueue.DepositMinRequestDurationSet(minRequestDuration);

        vm.prank(admin);
        depositQueue.setDepositMinRequestDuration(minRequestDuration);

        assertEq(depositQueue.getDepositMinRequestDuration(), minRequestDuration, "min request duration not set");
    }

    function test_setDepositRestriction_fail_notAdminOrOwner() public {
        address randomUser = makeAddr("randomUser");
        ERC7540LikeDepositQueue.DepositRestriction restriction =
        ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistInternal;

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        depositQueue.setDepositRestriction(restriction);
    }

    function test_setDepositRestriction_success() public {
        ERC7540LikeDepositQueue.DepositRestriction restriction =
        ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistInternal;

        vm.expectEmit(address(depositQueue));
        emit ERC7540LikeDepositQueue.DepositRestrictionSet(restriction);

        vm.prank(admin);
        depositQueue.setDepositRestriction(restriction);

        assertEq(uint8(depositQueue.getDepositRestriction()), uint8(restriction), "restriction not set");
    }

    function test_setDepositControllerExternalAllowlist_fail_notAdminOrOwner() public {
        address randomUser = makeAddr("randomUser");
        address allowlist = address(new BlankAddressList());

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        depositQueue.setDepositControllerExternalAllowlist(allowlist);
    }

    function test_setDepositControllerExternalAllowlist_success() public {
        address allowlist = address(new BlankAddressList());

        vm.expectEmit(address(depositQueue));
        emit ERC7540LikeDepositQueue.DepositControllerExternalAllowlistSet(allowlist);

        vm.prank(admin);
        depositQueue.setDepositControllerExternalAllowlist(allowlist);

        assertEq(address(depositQueue.getDepositControllerExternalAllowlist()), allowlist, "allowlist not set");
    }

    //==================================================================================================================
    // Required: IERC7540LikeDepositHandler
    //==================================================================================================================

    function test_cancelDeposit_fail_notRequestOwner() public {
        uint256 requestId = __test_cancelDeposit_setup();

        address randomUser = makeAddr("randomUser");
        vm.expectRevert(ERC7540LikeDepositQueue.ERC7540LikeDepositQueue__CancelRequest__Unauthorized.selector);
        vm.prank(randomUser);
        depositQueue.cancelDeposit(requestId);
    }

    function test_cancelDeposit_fail_minRequestDurationNotElapsed() public {
        uint256 requestId = __test_cancelDeposit_setup();
        address controller = depositQueue.getDepositRequest(requestId).controller;

        vm.expectRevert(
            ERC7540LikeDepositQueue.ERC7540LikeDepositQueue__CancelRequest__MinRequestDurationNotElapsed.selector
        );
        vm.prank(controller);
        depositQueue.cancelDeposit(requestId);
    }

    function test_cancelDeposit_success() public {
        uint256 requestId = __test_cancelDeposit_setup();

        // cancelable condition
        vm.warp(block.timestamp + depositQueue.getDepositMinRequestDuration());

        __test_cancelDeposit_success({_requestId: requestId});
    }

    function __test_cancelDeposit_setup() internal returns (uint256 requestId_) {
        // Create and set the deposit asset
        uint8 assetDecimals = 6;
        address depositAsset = address(new MockERC20(assetDecimals));
        vm.prank(admin);
        depositQueue.setAsset({_asset: depositAsset});

        // Define a controller, seed it with deposit asset, and grant allowance to the deposit queue
        address controller = makeAddr("controller");
        deal(depositAsset, controller, 1000 * 10 ** IERC20(depositAsset).decimals(), true);
        vm.prank(controller);
        IERC20(depositAsset).approve(address(depositQueue), type(uint256).max);

        // Set a min request time
        vm.prank(admin);
        depositQueue.setDepositMinRequestDuration(11);

        // Warp to an arbitrary time for the request
        uint256 requestTime = 123456;
        vm.warp(requestTime);

        // Create a request
        vm.prank(controller);
        return depositQueue.requestDeposit({_assets: 123, _controller: controller, _owner: controller});
    }

    function __test_cancelDeposit_success(uint256 _requestId) internal {
        address controller = depositQueue.getDepositRequest(_requestId).controller;
        uint256 depositAssetAmount = depositQueue.getDepositRequest(_requestId).assetAmount;
        IERC20 depositAsset = IERC20(depositQueue.asset());

        uint256 preControllerBalance = depositAsset.balanceOf(controller);

        vm.expectEmit(address(depositQueue));
        emit IERC7540LikeDepositHandler.DepositRequestCanceled(_requestId);

        vm.prank(controller);
        uint256 assetAmountRefunded = depositQueue.cancelDeposit(_requestId);

        // Deposit asset should be refunded
        assertEq(assetAmountRefunded, depositAssetAmount, "incorrect refund amount return value");
        assertEq(
            depositAsset.balanceOf(controller),
            preControllerBalance + depositAssetAmount,
            "refund not transferred to controller"
        );

        // Request should be zeroed out
        assertEq(depositQueue.getDepositRequest(_requestId).controller, address(0), "request not removed");
    }

    function test_requestDeposit_fail_ownerNotSender() public {
        address sender = makeAddr("sender");
        address controller = makeAddr("controller");
        address tokenOwner = controller;
        uint256 assetAmount = 123;
        __test_requestDeposit_setup({_tokenOwner: tokenOwner});

        vm.expectRevert(ERC7540LikeDepositQueue.ERC7540LikeDepositQueue__RequestDeposit__OwnerNotSender.selector);
        vm.prank(sender);
        depositQueue.requestDeposit({_assets: assetAmount, _controller: controller, _owner: tokenOwner});
    }

    function test_requestDeposit_fail_ownerNotController() public {
        address controller = makeAddr("controller");
        address tokenOwner = makeAddr("tokenOwner");
        uint256 assetAmount = 123;
        __test_requestDeposit_setup({_tokenOwner: tokenOwner});

        vm.expectRevert(ERC7540LikeDepositQueue.ERC7540LikeDepositQueue__RequestDeposit__OwnerNotController.selector);
        vm.prank(tokenOwner);
        depositQueue.requestDeposit({_assets: assetAmount, _controller: controller, _owner: tokenOwner});
    }

    function test_requestDeposit_fail_zeroAssets() public {
        address controller = makeAddr("controller");
        address tokenOwner = controller;
        __test_requestDeposit_setup({_tokenOwner: tokenOwner});

        vm.expectRevert(ERC7540LikeDepositQueue.ERC7540LikeDepositQueue__RequestDeposit__ZeroAssets.selector);
        vm.prank(tokenOwner);
        depositQueue.requestDeposit({_assets: 0, _controller: controller, _owner: tokenOwner});
    }

    function test_requestDeposit_fail_controllerNotAllowedInternal() public {
        address controller = makeAddr("controller");
        address tokenOwner = controller;
        uint256 assetAmount = 123;
        __test_requestDeposit_setup({_tokenOwner: tokenOwner});

        // Restrict controllers to internal allowlist
        vm.prank(admin);
        depositQueue.setDepositRestriction(ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistInternal);

        vm.expectRevert(ERC7540LikeDepositQueue.ERC7540LikeDepositQueue__RequestDeposit__ControllerNotAllowed.selector);
        vm.prank(tokenOwner);
        depositQueue.requestDeposit({_assets: assetAmount, _controller: controller, _owner: tokenOwner});
    }

    function test_requestDeposit_fail_controllerNotAllowedExternal() public {
        address controller = makeAddr("controller");
        address tokenOwner = controller;
        uint256 assetAmount = 123;
        __test_requestDeposit_setup({_tokenOwner: tokenOwner});

        // Create an external allowlist and set it
        address allowlist = address(new BlankAddressList());
        vm.prank(admin);
        depositQueue.setDepositControllerExternalAllowlist(allowlist);

        // Restrict controllers to external allowlist
        vm.prank(admin);
        depositQueue.setDepositRestriction(ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistExternal);

        // Mock the external allowlist to return false for the controller
        addressList_mockIsInList({_addressList: allowlist, _item: controller, _isInList: false});

        vm.expectRevert(ERC7540LikeDepositQueue.ERC7540LikeDepositQueue__RequestDeposit__ControllerNotAllowed.selector);
        vm.prank(tokenOwner);
        depositQueue.requestDeposit({_assets: assetAmount, _controller: controller, _owner: tokenOwner});
    }

    // Tests both requestDeposit() and requestDepositReferred()
    function test_requestDeposit_success() public {
        address controller = makeAddr("controller");
        address tokenOwner = controller;
        __test_requestDeposit_setup({_tokenOwner: tokenOwner});

        __test_requestDeposit_success({
            _controller: controller,
            _tokenOwner: tokenOwner,
            _assetAmount: 123,
            _referred: false,
            _depositRestriction: ERC7540LikeDepositQueue.DepositRestriction.None
        });
        // Use internal controller allowlist
        __test_requestDeposit_success({
            _controller: controller,
            _tokenOwner: tokenOwner,
            _assetAmount: 456,
            _referred: true,
            _depositRestriction: ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistInternal
        });
        // Use external controller allowlist
        __test_requestDeposit_success({
            _controller: controller,
            _tokenOwner: tokenOwner,
            _assetAmount: 789,
            _referred: false,
            _depositRestriction: ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistExternal
        });
    }

    function __test_requestDeposit_success(
        address _controller,
        address _tokenOwner,
        uint256 _assetAmount,
        bool _referred,
        ERC7540LikeDepositQueue.DepositRestriction _depositRestriction
    ) internal {
        if (_depositRestriction == ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistInternal) {
            // Add the controller to the internal allowlist
            if (!depositQueue.isInDepositControllerInternalAllowlist(_controller)) {
                vm.prank(admin);
                depositQueue.addDepositControllerToInternalAllowlist(_controller);
            }

            // Set the deposit restriction to internal allowlist
            vm.prank(admin);
            depositQueue.setDepositRestriction(ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistInternal);
        } else if (_depositRestriction == ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistExternal) {
            // Remove the controller from the internal allowlist
            vm.prank(admin);
            if (depositQueue.isInDepositControllerInternalAllowlist(_controller)) {
                vm.prank(admin);
                depositQueue.removeDepositControllerFromInternalAllowlist(_controller);
            }

            // Create a new external allowlist
            address addressList = address(new BlankAddressList());
            addressList_mockIsInList({_addressList: addressList, _item: _controller, _isInList: true});

            // Set the deposit restriction to external allowlist and set the external allowlist
            vm.startPrank(admin);
            depositQueue.setDepositRestriction(ERC7540LikeDepositQueue.DepositRestriction.ControllerAllowlistExternal);
            depositQueue.setDepositControllerExternalAllowlist(addressList);
            vm.stopPrank();
        } else if (_depositRestriction == ERC7540LikeDepositQueue.DepositRestriction.None) {
            // Do nothing
        } else {
            revert("Invalid deposit restriction");
        }

        uint256 expectedRequestId = depositQueue.getDepositLastId() + 1;
        uint256 expectedCanCancelTime = block.timestamp + depositQueue.getDepositMinRequestDuration();

        IERC20 asset = IERC20(depositQueue.asset());
        uint256 preRequestQueueAssetBalance = asset.balanceOf(address(depositQueue));
        uint256 preRequestTokenOwnerAssetBalance = asset.balanceOf(_tokenOwner);

        vm.expectEmit(address(depositQueue));
        emit IERC7540LikeDepositHandler.DepositRequest({
            controller: _controller,
            owner: _tokenOwner,
            requestId: expectedRequestId,
            sender: _tokenOwner,
            assets: _assetAmount
        });

        if (_referred) {
            bytes32 referrer = "test";

            vm.expectEmit(address(depositQueue));
            emit IERC7540LikeDepositHandler.DepositRequestReferred({requestId: expectedRequestId, referrer: referrer});

            vm.prank(_tokenOwner);
            depositQueue.requestDepositReferred({
                _assets: _assetAmount, _controller: _controller, _owner: _tokenOwner, _referrer: referrer
            });
        } else {
            vm.prank(_tokenOwner);
            depositQueue.requestDeposit({_assets: _assetAmount, _controller: _controller, _owner: _tokenOwner});
        }

        // Assert request storage
        ERC7540LikeDepositQueue.DepositRequestInfo memory request = depositQueue.getDepositRequest(expectedRequestId);
        assertEq(request.controller, _controller, "incorrect controller");
        assertEq(request.assetAmount, _assetAmount, "incorrect asset amount");
        assertEq(request.canCancelTime, expectedCanCancelTime, "incorrect can cancel time");

        // Assert asset transfer
        assertEq(
            asset.balanceOf(address(depositQueue)),
            preRequestQueueAssetBalance + _assetAmount,
            "incorrect final queue asset balance"
        );
        assertEq(
            asset.balanceOf(_tokenOwner),
            preRequestTokenOwnerAssetBalance - _assetAmount,
            "incorrect final token owner asset balance"
        );
    }

    function __test_requestDeposit_setup(address _tokenOwner) internal {
        // Create and set the asset
        uint8 assetDecimals = 6;
        address asset = address(new MockERC20(assetDecimals));
        vm.prank(admin);
        depositQueue.setAsset({_asset: asset});

        // Seed token owner with asset, and grant allowance to the queue
        deal(asset, _tokenOwner, 1000 * 10 ** IERC20(asset).decimals(), true);
        vm.prank(_tokenOwner);
        IERC20(asset).approve(address(depositQueue), type(uint256).max);

        // Set a min request time
        vm.prank(admin);
        depositQueue.setDepositMinRequestDuration(11);

        // Warp to an arbitrary time for the request
        uint256 requestTime = 123456;
        vm.warp(requestTime);
    }

    //==================================================================================================================
    // Request fulfillment
    //==================================================================================================================

    function test_executeDepositRequests_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);
        vm.prank(randomUser);
        depositQueue.executeDepositRequests({_requestIds: new uint256[](0)});
    }

    // Queues 3 requests, and executes 2 of them
    function __test_executeDepositRequests_setup() private returns (ExecuteDepositSetupData memory data_) {
        // Define requests
        data_.request1Controller = makeAddr("controller1");
        address request2Controller = makeAddr("controller2");
        data_.request3Controller = makeAddr("controller3");

        data_.request1AssetAmount = 5_000_000; // 5 units with 6 decimals
        data_.request3AssetAmount = 10_000_000; // 10 units with 6 decimals

        uint128 depositAssetToValueAssetRate = 4e18; // 1 depositAsset : 4 valueAsset
        // sharePrice = 1e18; // Keep it simple with 1:1 share price

        uint256 request1GrossSharesAmount = 20e18; // 5 shares * 4 rate = 20 shares
        uint256 request3GrossSharesAmount = 40e18; // 10 shares * 4 rate = 40 shares

        uint256 request1FeeSharesAmount = 1e18; // 10% fee of 10 shares
        uint256 request3FeeSharesAmount = 2e18; // 10% fee of 20 shares

        data_.request1ExpectedSharesAmount = request1GrossSharesAmount - request1FeeSharesAmount;
        data_.request3ExpectedSharesAmount = request3GrossSharesAmount - request3FeeSharesAmount;

        // Create and set the asset
        uint8 assetDecimals = 6;
        data_.asset = address(new MockERC20(assetDecimals));
        vm.prank(admin);
        depositQueue.setAsset({_asset: data_.asset});

        // Set the asset rate
        vm.prank(admin);
        valuationHandler.setAssetRate(
            ValuationHandler.AssetRateInput({
                asset: data_.asset, rate: depositAssetToValueAssetRate, expiry: uint40(block.timestamp + 1)
            })
        );

        // Mock and set a fee handler with different fee amounts for each request shares amount
        address mockFeeHandler = makeAddr("mockFeeHandler");
        feeHandler_mockSettleEntranceFeeGivenGrossShares({
            _feeHandler: mockFeeHandler,
            _feeSharesAmount: request1FeeSharesAmount,
            _grossSharesAmount: request1GrossSharesAmount
        });
        feeHandler_mockSettleEntranceFeeGivenGrossShares({
            _feeHandler: mockFeeHandler,
            _feeSharesAmount: request3FeeSharesAmount,
            _grossSharesAmount: request3GrossSharesAmount
        });

        vm.prank(admin);
        shares.setFeeHandler(mockFeeHandler);

        // Seed controllers with asset, and grant allowance to the queue
        address[3] memory controllers = [data_.request1Controller, request2Controller, data_.request3Controller];
        for (uint256 i; i < controllers.length; i++) {
            deal(data_.asset, controllers[i], 1000 * 10 ** IERC20(data_.asset).decimals(), true);
            vm.prank(controllers[i]);
            IERC20(data_.asset).approve(address(depositQueue), type(uint256).max);
        }

        // Create the requests
        vm.prank(data_.request1Controller);
        depositQueue.requestDeposit({
            _assets: data_.request1AssetAmount, _controller: data_.request1Controller, _owner: data_.request1Controller
        });
        vm.prank(request2Controller);
        depositQueue.requestDeposit({_assets: 456, _controller: request2Controller, _owner: request2Controller});
        vm.prank(data_.request3Controller);
        depositQueue.requestDeposit({
            _assets: data_.request3AssetAmount, _controller: data_.request3Controller, _owner: data_.request3Controller
        });
    }

    function test_executeDepositRequests_success() public {
        ExecuteDepositSetupData memory d = __test_executeDepositRequests_setup();

        // Define ids to execute: first and last items
        uint256[] memory requestIdsToExecute = new uint256[](2);
        requestIdsToExecute[0] = 1;
        requestIdsToExecute[1] = 3;

        // Pre-assert events
        vm.expectEmit(address(depositQueue));
        emit IERC7540LikeDepositHandler.Deposit({
            sender: d.request1Controller,
            owner: d.request1Controller,
            assets: d.request1AssetAmount,
            shares: d.request1ExpectedSharesAmount
        });
        vm.expectEmit(address(depositQueue));
        emit IERC7540LikeDepositHandler.DepositRequestExecuted({
            requestId: 1, sharesAmount: d.request1ExpectedSharesAmount
        });

        vm.expectEmit(address(depositQueue));
        emit IERC7540LikeDepositHandler.Deposit({
            sender: d.request3Controller,
            owner: d.request3Controller,
            assets: d.request3AssetAmount,
            shares: d.request3ExpectedSharesAmount
        });
        vm.expectEmit(address(depositQueue));
        emit IERC7540LikeDepositHandler.DepositRequestExecuted({
            requestId: 3, sharesAmount: d.request3ExpectedSharesAmount
        });

        // Execute the requests
        vm.prank(admin);
        depositQueue.executeDepositRequests({_requestIds: requestIdsToExecute});

        // Assert shares sent
        assertEq(
            shares.balanceOf(d.request1Controller),
            d.request1ExpectedSharesAmount,
            "incorrect final shares balance for request 1"
        );
        assertEq(
            shares.balanceOf(d.request3Controller),
            d.request3ExpectedSharesAmount,
            "incorrect final shares balance for request 3"
        );

        // Assert assets sent to Shares
        assertEq(
            IERC20(d.asset).balanceOf(address(shares)),
            d.request1AssetAmount + d.request3AssetAmount,
            "incorrect final asset balance in Shares"
        );

        // Assert requests are removed
        assertEq(depositQueue.getDepositRequest(1).controller, address(0), "request 1 not removed");
        assertEq(depositQueue.getDepositRequest(3).controller, address(0), "request 3 not removed");
    }
}
