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

import {AccountERC20Tracker} from "src/components/value/position-trackers/AccountERC20Tracker.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {IValuationHandler} from "src/interfaces/IValuationHandler.sol";
import {Shares} from "src/shares/Shares.sol";

import {AccountERC20TrackerHarness} from "test/harnesses/AccountERC20TrackerHarness.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract AccountERC20TrackerTest is Test, TestHelpers {
    Shares shares;
    address owner;
    address admin = makeAddr("admin");
    address trackedAccount = makeAddr("trackedAccount");
    address mockValuationHandler = makeAddr("mockValuationHandler");

    AccountERC20Tracker tracker;
    MockERC20 token1;
    MockERC20 token2;

    function setUp() public {
        shares = createShares();
        owner = shares.owner();

        vm.prank(owner);
        shares.addAdmin(admin);

        // Set valuation handler on Shares
        vm.prank(admin);
        shares.setValuationHandler(mockValuationHandler);

        // Create the tracker, initialized with tracked account
        tracker = AccountERC20Tracker(address(new AccountERC20TrackerHarness({_shares: address(shares)})));
        tracker.init(trackedAccount);

        // Create mock tokens
        token1 = new MockERC20(18);
        token2 = new MockERC20(6);

        // Mint tokens to tracked account
        token1.mintTo(trackedAccount, 1000e18);
        token2.mintTo(trackedAccount, 500e6);
    }

    //==================================================================================================================
    // Init
    //==================================================================================================================

    function test_init_fail_alreadyInitialized() public {
        // Already initialized in setup

        address newAccount = makeAddr("newAccount");

        // Try to initialize again
        vm.expectRevert(AccountERC20Tracker.AccountERC20Tracker__Init__AlreadyInitialized.selector);

        vm.prank(admin);
        tracker.init(newAccount);
    }

    function test_init_fail_emptyAccount() public {
        // Create a new tracker for this test
        AccountERC20Tracker newTracker =
            AccountERC20Tracker(address(new AccountERC20TrackerHarness({_shares: address(shares)})));

        vm.expectRevert(AccountERC20Tracker.AccountERC20Tracker__Init__EmptyAccount.selector);

        // Try to initialize with address(0)
        vm.prank(admin);
        newTracker.init(address(0));
    }

    function test_init_success() public {
        // Create a new tracker for this test
        AccountERC20Tracker newTracker =
            AccountERC20Tracker(address(new AccountERC20TrackerHarness({_shares: address(shares)})));

        vm.expectEmit();
        emit AccountERC20Tracker.AccountSet(trackedAccount);

        vm.prank(admin);
        newTracker.init(trackedAccount);

        assertEq(newTracker.getAccount(), trackedAccount);
    }

    //==================================================================================================================
    // Config (access: admin)
    //==================================================================================================================

    function test_addAsset_fail_onlyAdminOrOwner() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        tracker.addAsset(address(token1));
    }

    function test_addAsset_fail_alreadyAdded() public {
        // First add the asset
        vm.prank(admin);
        tracker.addAsset(address(token1));

        // Try to add the same asset again
        vm.expectRevert(AccountERC20Tracker.AccountERC20Tracker__AddAsset__AlreadyAdded.selector);

        vm.prank(admin);
        tracker.addAsset(address(token1));
    }

    function test_addAsset_success() public {
        assertFalse(tracker.isAsset(address(token1)));

        vm.expectEmit();
        emit AccountERC20Tracker.AssetAdded(address(token1));

        vm.prank(admin);
        tracker.addAsset(address(token1));

        assertTrue(tracker.isAsset(address(token1)));

        address[] memory assets = tracker.getAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(token1));
    }

    function test_removeAsset_fail_onlyAdminOrOwner() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        tracker.removeAsset(address(token1));
    }

    function test_removeAsset_fail_notAdded() public {
        vm.expectRevert(AccountERC20Tracker.AccountERC20Tracker__RemoveAsset__NotAdded.selector);

        vm.prank(admin);
        tracker.removeAsset(address(token1));
    }

    function test_removeAsset_success() public {
        // First add the assets
        vm.startPrank(admin);
        tracker.addAsset(address(token1));
        tracker.addAsset(address(token2));
        vm.stopPrank();

        vm.expectEmit();
        emit AccountERC20Tracker.AssetRemoved(address(token1));

        vm.prank(admin);
        tracker.removeAsset(address(token1));

        assertFalse(tracker.isAsset(address(token1)));
        assertTrue(tracker.isAsset(address(token2)));

        address[] memory assets = tracker.getAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(token2));
    }

    //==================================================================================================================
    // Position value
    //==================================================================================================================

    function test_getPositionValue_fail_notInitialized() public {
        // Create a new uninitialized tracker
        AccountERC20Tracker newTracker =
            AccountERC20Tracker(address(new AccountERC20TrackerHarness({_shares: address(shares)})));

        vm.expectRevert(AccountERC20Tracker.AccountERC20Tracker__GetPositionValue__NotInitialized.selector);

        // Try to get position value before initialization
        newTracker.getPositionValue();
    }

    function test_getPositionValue_success() public {
        // Set up the tracker with assets (account already set in setUp)
        vm.startPrank(admin);
        tracker.addAsset(address(token1));
        tracker.addAsset(address(token2));
        vm.stopPrank();

        // Define expected values
        uint256 token1TotalValue = 100;
        uint256 token2TotalValue = 800;
        uint256 totalValue = 900;

        // Mock valuation handler responses for the specific token amounts
        vm.mockCall(
            mockValuationHandler,
            abi.encodeWithSelector(
                IValuationHandler.convertAssetAmountToValue.selector, address(token1), token1.balanceOf(trackedAccount)
            ),
            abi.encode(token1TotalValue)
        );

        vm.mockCall(
            mockValuationHandler,
            abi.encodeWithSelector(
                IValuationHandler.convertAssetAmountToValue.selector, address(token2), token2.balanceOf(trackedAccount)
            ),
            abi.encode(token2TotalValue)
        );

        // Test position value
        int256 positionValue = tracker.getPositionValue();
        assertEq(positionValue, int256(totalValue));
    }
}
