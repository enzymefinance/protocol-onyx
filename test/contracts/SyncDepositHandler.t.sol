// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {SyncDepositHandler} from "src/components/issuance/deposit-handlers/SyncDepositHandler.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {Shares} from "src/shares/Shares.sol";

import {SyncDepositHandlerHarness} from "test/harnesses/SyncDepositHandlerHarness.sol";
import {ValuationHandlerHarness} from "test/harnesses/ValuationHandlerHarness.sol";
import {BlankAddressList} from "test/mocks/Blanks.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract SyncDepositHandlerTest is TestHelpers {
    Shares shares;
    address owner;
    address admin = makeAddr("admin");
    address depositor = makeAddr("depositor");
    ValuationHandlerHarness valuationHandler;

    SyncDepositHandlerHarness depositHandler;

    // Deposit asset: 6 decimals
    address depositAsset;
    uint8 constant ASSET_DECIMALS = 6;

    function setUp() public {
        // Warp to arbitrary initial time
        vm.warp(100);

        shares = createShares();
        owner = shares.owner();

        vm.prank(owner);
        shares.addAdmin(admin);

        // Create deposit asset
        depositAsset = address(new MockERC20(ASSET_DECIMALS));

        // Deploy harness and register as deposit handler
        depositHandler = new SyncDepositHandlerHarness(address(shares));
        depositHandler.init(depositAsset);
        vm.prank(admin);
        shares.addDepositHandler(address(depositHandler));

        // Deploy and set ValuationHandler
        valuationHandler = new ValuationHandlerHarness(address(shares));
        vm.prank(admin);
        shares.setValuationHandler(address(valuationHandler));

        // Seed depositor with assets and approval
        deal(depositAsset, depositor, 1000e6, true);
        vm.prank(depositor);
        IERC20(depositAsset).approve(address(depositHandler), type(uint256).max);
    }

    //==================================================================================================================
    // Init
    //==================================================================================================================

    function test_init_success() public {
        SyncDepositHandlerHarness handler = new SyncDepositHandlerHarness(address(shares));
        address asset = makeAddr("asset");

        vm.expectEmit(address(handler));
        emit SyncDepositHandler.AssetSet(asset);

        handler.init(asset);

        assertEq(handler.getAsset(), asset, "asset not set");
        assertEq(handler.getDepositorAllowlist(), address(0), "depositorAllowlist should default to address(0)");
        assertEq(handler.getMaxSharePriceStaleness(), 0, "staleness should default to 0");
    }

    //==================================================================================================================
    // Config: setMaxSharePriceStaleness
    //==================================================================================================================

    function test_setMaxSharePriceStaleness_fail_notAdminOrOwner() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);
        vm.prank(randomUser);
        depositHandler.setMaxSharePriceStaleness(100);
    }

    function test_setMaxSharePriceStaleness_success() public {
        uint24 maxStaleness = 3600;

        vm.expectEmit(address(depositHandler));
        emit SyncDepositHandler.MaxSharePriceStalenessSet({maxStaleness: maxStaleness});

        vm.prank(admin);
        depositHandler.setMaxSharePriceStaleness(maxStaleness);

        assertEq(depositHandler.getMaxSharePriceStaleness(), maxStaleness, "staleness not set");
    }

    //==================================================================================================================
    // Config: setDepositorAllowlist
    //==================================================================================================================

    function test_setDepositorAllowlist_fail_notAdminOrOwner() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);
        vm.prank(randomUser);
        depositHandler.setDepositorAllowlist(address(0));
    }

    function test_setDepositorAllowlist_success() public {
        address list = address(new BlankAddressList());

        // Set allowlist
        vm.expectEmit(address(depositHandler));
        emit SyncDepositHandler.DepositorAllowlistSet({list: list});

        vm.prank(admin);
        depositHandler.setDepositorAllowlist(list);

        assertEq(depositHandler.getDepositorAllowlist(), list, "list not set");

        // Clear allowlist
        vm.expectEmit(address(depositHandler));
        emit SyncDepositHandler.DepositorAllowlistSet({list: address(0)});

        vm.prank(admin);
        depositHandler.setDepositorAllowlist(address(0));

        assertEq(depositHandler.getDepositorAllowlist(), address(0), "list not cleared");
    }

    //==================================================================================================================
    // Deposit
    //==================================================================================================================

    function test_deposit_fail_zeroAssets() public {
        valuationHandler.harness_setLastShareValue({_shareValue: 1e18, _timestamp: block.timestamp});

        vm.expectRevert(SyncDepositHandler.SyncDepositHandler__Deposit__ZeroAssets.selector);
        vm.prank(depositor);
        depositHandler.deposit({_assetAmount: 0});
    }

    function test_deposit_fail_depositorNotAllowed() public {
        valuationHandler.harness_setLastShareValue({_shareValue: 1e18, _timestamp: block.timestamp});

        // Set an allowlist that does not include depositor
        address list = address(new BlankAddressList());
        addressList_mockIsInList({_addressList: list, _item: depositor, _isInList: false});
        vm.prank(admin);
        depositHandler.setDepositorAllowlist(list);

        vm.expectRevert(SyncDepositHandler.SyncDepositHandler__ValidateDepositor__DepositorNotAllowed.selector);
        vm.prank(depositor);
        depositHandler.deposit({_assetAmount: 100e6});
    }

    function test_deposit_fail_sharePriceStale() public {
        valuationHandler.harness_setLastShareValue({_shareValue: 1e18, _timestamp: block.timestamp});

        // Set staleness to 60 seconds
        vm.prank(admin);
        depositHandler.setMaxSharePriceStaleness(60);

        // Warp so share price is stale
        vm.warp(block.timestamp + 61);

        vm.expectRevert(SyncDepositHandler.SyncDepositHandler__ValidateSharePriceTimestamp__SharePriceStale.selector);
        vm.prank(depositor);
        depositHandler.deposit({_assetAmount: 100e6});
    }

    function test_deposit_fail_zeroShares() public {
        uint128 assetRate = 5e18; // 1:5: 1 asset = 5 value asset
        vm.prank(admin);
        valuationHandler.setAssetRate(
            ValuationHandler.AssetRateInput({asset: depositAsset, rate: assetRate, expiry: uint40(type(uint40).max)})
        );

        // Set share price very high so deposit amount rounds to 0 shares
        valuationHandler.harness_setLastShareValue({_shareValue: type(uint128).max, _timestamp: block.timestamp});

        vm.expectRevert(SyncDepositHandler.SyncDepositHandler__Deposit__ZeroShares.selector);
        vm.prank(depositor);
        depositHandler.deposit({_assetAmount: 1});
    }

    // Tests both deposit() and depositReferred()
    function test_deposit_success() public {
        valuationHandler.harness_setLastShareValue({_shareValue: 1e18, _timestamp: block.timestamp});

        uint128 assetRate = 5e18; // 1:5: 1 asset = 5 value asset
        vm.prank(admin);
        valuationHandler.setAssetRate(
            ValuationHandler.AssetRateInput({asset: depositAsset, rate: assetRate, expiry: uint40(type(uint40).max)})
        );

        // 1:5 rate, 1:1 share price => 500e18 shares (no fee handler set)
        __test_deposit_success({_referred: false, _depositAmount: 100e6, _expectedShares: 500e18});
        __test_deposit_success({_referred: true, _depositAmount: 100e6, _expectedShares: 500e18});
    }

    function test_deposit_success_withAllowList() public {
        valuationHandler.harness_setLastShareValue({_shareValue: 1e18, _timestamp: block.timestamp});

        uint128 assetRate = 5e18; // 1:5: 1 asset = 5 value asset
        vm.prank(admin);
        valuationHandler.setAssetRate(
            ValuationHandler.AssetRateInput({asset: depositAsset, rate: assetRate, expiry: uint40(type(uint40).max)})
        );

        // Set allowlist that includes the depositor
        address list = address(new BlankAddressList());
        addressList_mockIsInList({_addressList: list, _item: depositor, _isInList: true});
        vm.prank(admin);
        depositHandler.setDepositorAllowlist(list);

        // 1:5 rate, 1:1 share price => 500e18 shares
        __test_deposit_success({_referred: false, _depositAmount: 100e6, _expectedShares: 500e18});
    }

    function test_deposit_success_withFee() public {
        valuationHandler.harness_setLastShareValue({_shareValue: 1e18, _timestamp: block.timestamp});

        uint128 assetRate = 5e18; // 1:5: 1 asset = 5 value asset
        vm.prank(admin);
        valuationHandler.setAssetRate(
            ValuationHandler.AssetRateInput({asset: depositAsset, rate: assetRate, expiry: uint40(type(uint40).max)})
        );

        // 1:5 rate, 1:1 share price => 500e18 gross shares
        uint256 grossShares = 500e18;
        uint256 feeShares = 5e18;
        uint256 expectedNetShares = 495e18; // grossShares - feeShares;

        // Mock fee handler
        address mockFeeHandler = makeAddr("mockFeeHandler");
        feeHandler_mockSettleEntranceFeeGivenGrossShares({
            _feeHandler: mockFeeHandler, _feeSharesAmount: feeShares, _grossSharesAmount: grossShares
        });
        vm.prank(admin);
        shares.setFeeHandler(mockFeeHandler);

        __test_deposit_success({_referred: false, _depositAmount: 100e6, _expectedShares: expectedNetShares});
    }

    function test_deposit_success_sharePriceNotStaleAtBoundary() public {
        valuationHandler.harness_setLastShareValue({_shareValue: 1e18, _timestamp: block.timestamp});

        uint128 assetRate = 5e18; // 1:5: 1 asset = 5 value asset
        vm.prank(admin);
        valuationHandler.setAssetRate(
            ValuationHandler.AssetRateInput({asset: depositAsset, rate: assetRate, expiry: uint40(type(uint40).max)})
        );

        // Set staleness to 60 seconds
        vm.prank(admin);
        depositHandler.setMaxSharePriceStaleness(60);

        // Warp exactly to the boundary (not stale yet)
        vm.warp(block.timestamp + 60);

        // 1:5 rate, 1:1 share price => 500e18 shares
        __test_deposit_success({_referred: false, _depositAmount: 100e6, _expectedShares: 500e18});
    }

    function __test_deposit_success(bool _referred, uint256 _depositAmount, uint256 _expectedShares) internal {
        uint256 preDepositorAssetBalance = IERC20(depositAsset).balanceOf(depositor);
        uint256 preSharesAssetBalance = IERC20(depositAsset).balanceOf(address(shares));
        uint256 preDepositorSharesBalance = shares.balanceOf(depositor);

        uint256 sharesReceived;
        if (_referred) {
            bytes32 referrer = "test-referrer";

            vm.expectEmit(address(depositHandler));
            emit SyncDepositHandler.Deposit({
                depositor: depositor, assetAmount: _depositAmount, sharesAmount: _expectedShares, referrer: referrer
            });

            vm.prank(depositor);
            sharesReceived = depositHandler.depositReferred({_assetAmount: _depositAmount, _referrer: referrer});
        } else {
            vm.expectEmit(address(depositHandler));
            emit SyncDepositHandler.Deposit({
                depositor: depositor, assetAmount: _depositAmount, sharesAmount: _expectedShares, referrer: bytes32(0)
            });

            vm.prank(depositor);
            sharesReceived = depositHandler.deposit({_assetAmount: _depositAmount});
        }

        // Assert shares minted
        assertEq(sharesReceived, _expectedShares, "incorrect shares return value");
        assertEq(shares.balanceOf(depositor), preDepositorSharesBalance + _expectedShares, "incorrect shares balance");

        // Assert asset transferred from depositor to Shares
        assertEq(
            IERC20(depositAsset).balanceOf(depositor),
            preDepositorAssetBalance - _depositAmount,
            "incorrect depositor asset balance"
        );
        assertEq(
            IERC20(depositAsset).balanceOf(address(shares)),
            preSharesAssetBalance + _depositAmount,
            "incorrect Shares asset balance"
        );
    }
}
