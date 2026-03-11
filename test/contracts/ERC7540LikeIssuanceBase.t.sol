// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {ERC7540LikeIssuanceBase} from "src/components/issuance/utils/ERC7540LikeIssuanceBase.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {Shares} from "src/shares/Shares.sol";

import {ERC7540LikeIssuanceBaseHarness} from "test/harnesses/ERC7540LikeIssuanceBaseHarness.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract ERC7540LikeIssuanceBaseTest is TestHelpers {
    Shares shares;
    address owner;
    address admin = makeAddr("admin");

    ERC7540LikeIssuanceBaseHarness issuanceBase;

    function setUp() public {
        shares = createShares();
        owner = shares.owner();

        vm.prank(owner);
        shares.addAdmin(admin);

        // Deploy issuance base
        issuanceBase = new ERC7540LikeIssuanceBaseHarness(address(shares));
    }

    //==================================================================================================================
    // Config (access: admin or owner)
    //==================================================================================================================

    function test_setAsset_fail_notAdminOrOwner() public {
        address randomUser = makeAddr("randomUser");
        address asset = makeAddr("asset");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        issuanceBase.setAsset(asset);
    }

    function test_setAsset_fail_alreadySet() public {
        address asset = makeAddr("asset");

        vm.prank(admin);
        issuanceBase.setAsset(asset);

        vm.expectRevert(ERC7540LikeIssuanceBase.ERC7540LikeIssuanceBase__SetAsset__AlreadySet.selector);

        vm.prank(admin);
        issuanceBase.setAsset(asset);
    }

    function test_setAsset_success() public {
        address asset = makeAddr("asset");

        vm.expectEmit();
        emit ERC7540LikeIssuanceBase.AssetSet({asset: asset});

        vm.prank(admin);
        issuanceBase.setAsset(asset);

        assertEq(issuanceBase.asset(), asset);
    }

    //==================================================================================================================
    // IERC7575
    //==================================================================================================================

    function test_share_success() public view {
        assertEq(issuanceBase.share(), address(shares));
    }
}
