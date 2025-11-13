// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IFeeHandler} from "src/interfaces/IFeeHandler.sol";
import {ISharesTransferValidator} from "src/interfaces/ISharesTransferValidator.sol";
import {Shares} from "src/shares/Shares.sol";

import {BlankFeeHandler, BlankSharesTransferValidator} from "test/mocks/Blanks.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract SharesInitTest is Test {
    struct TestInitParams {
        address owner;
        string name;
        string symbol;
        bytes32 valueAsset;
    }

    TestInitParams testInitParams =
        TestInitParams({owner: makeAddr("owner"), name: "Test Shares", symbol: "TST", valueAsset: keccak256("USD")});

    function test_init_fail_calledTwice() public {
        Shares shares = new Shares();

        shares.init({
            _owner: testInitParams.owner,
            _name: testInitParams.name,
            _symbol: testInitParams.symbol,
            _valueAsset: testInitParams.valueAsset
        });

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        shares.init({
            _owner: testInitParams.owner,
            _name: testInitParams.name,
            _symbol: testInitParams.symbol,
            _valueAsset: testInitParams.valueAsset
        });
    }

    function test_init_fail_noName() public {
        Shares shares = new Shares();

        vm.expectRevert(Shares.Shares__Init__EmptyName.selector);
        shares.init({
            _owner: testInitParams.owner,
            _name: "",
            _symbol: testInitParams.symbol,
            _valueAsset: testInitParams.valueAsset
        });
    }

    function test_init_fail_noSymbol() public {
        Shares shares = new Shares();

        vm.expectRevert(Shares.Shares__Init__EmptySymbol.selector);
        shares.init({
            _owner: testInitParams.owner,
            _name: testInitParams.name,
            _symbol: "",
            _valueAsset: testInitParams.valueAsset
        });
    }

    function test_init_success() public {
        Shares shares = new Shares();

        address owner = testInitParams.owner;
        string memory name = testInitParams.name;
        string memory symbol = testInitParams.symbol;
        bytes32 valueAsset = testInitParams.valueAsset;

        shares.init({_owner: owner, _name: name, _symbol: symbol, _valueAsset: valueAsset});

        assertEq(shares.owner(), owner);
        assertEq(shares.name(), name);
        assertEq(shares.symbol(), symbol);
        assertEq(shares.getValueAsset(), valueAsset);
    }
}

contract SharesTest is Test, TestHelpers {
    Shares shares;
    address owner;
    address admin = makeAddr("SharesTest.admin");

    function setUp() public {
        shares = createShares();
        owner = shares.owner();

        vm.prank(owner);
        shares.addAdmin(admin);
    }

    //==================================================================================================================
    // Config (access: owner)
    //==================================================================================================================

    function test_addAdmin_fail_alreadyAdded() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(owner);
        shares.addAdmin(newAdmin);

        // Second call should fail
        vm.expectRevert(Shares.Shares__AddAdmin__AlreadyAdded.selector);
        vm.prank(owner);
        shares.addAdmin(newAdmin);
    }

    function test_addAdmin_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");
        address newAdmin = makeAddr("newAdmin");

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, randomUser));
        vm.prank(randomUser);
        shares.addAdmin(newAdmin);
    }

    function test_addAdmin_success() public {
        address newAdmin = makeAddr("newAdmin");

        assertFalse(shares.isAdmin(newAdmin));

        vm.expectEmit(address(shares));
        emit Shares.AdminAdded(newAdmin);

        vm.prank(owner);
        shares.addAdmin(newAdmin);

        assertTrue(shares.isAdmin(newAdmin));
    }

    function test_removeAdmin_fail_alreadyRemoved() public {
        address newAdmin = makeAddr("newAdmin");

        vm.expectRevert(Shares.Shares__RemoveAdmin__AlreadyRemoved.selector);
        vm.prank(owner);
        shares.removeAdmin(newAdmin);
    }

    function test_removeAdmin_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");
        address newAdmin = makeAddr("newAdmin");

        vm.prank(owner);
        shares.addAdmin(newAdmin);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, randomUser));
        vm.prank(randomUser);
        shares.removeAdmin(newAdmin);
    }

    function test_removeAdmin_success() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(owner);
        shares.addAdmin(newAdmin);

        vm.expectEmit(address(shares));
        emit Shares.AdminRemoved(newAdmin);

        vm.prank(owner);
        shares.removeAdmin(newAdmin);

        assertFalse(shares.isAdmin(newAdmin));
    }

    //==================================================================================================================
    // Config (access: admin or owner)
    //==================================================================================================================

    function test_isAdminOrOwner_success() public {
        address randomUser = makeAddr("randomUser");

        assertTrue(shares.isAdminOrOwner(owner));
        assertTrue(shares.isAdminOrOwner(admin));
        assertFalse(shares.isAdminOrOwner(randomUser));
    }

    // SYSTEM CONTRACTS

    function test_addDepositHandler_fail_alreadyAdded() public {
        address newDepositHandler = makeAddr("newDepositHandler");

        vm.prank(admin);
        shares.addDepositHandler(newDepositHandler);

        // Second call should fail
        vm.expectRevert(Shares.Shares__AddDepositHandler__AlreadyAdded.selector);
        vm.prank(admin);
        shares.addDepositHandler(newDepositHandler);
    }

    function test_addDepositHandler_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");
        address newDepositHandler = makeAddr("newDepositHandler");

        vm.expectRevert(Shares.Shares__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        shares.addDepositHandler(newDepositHandler);
    }

    function test_addDepositHandler_success() public {
        address newDepositHandler = makeAddr("newDepositHandler");

        vm.expectEmit(address(shares));
        emit Shares.DepositHandlerAdded(newDepositHandler);

        vm.prank(admin);
        shares.addDepositHandler(newDepositHandler);

        assertTrue(shares.isDepositHandler(newDepositHandler));
    }

    function test_addRedeemHandler_fail_alreadyAdded() public {
        address newRedeemHandler = makeAddr("newRedeemHandler");

        vm.prank(admin);
        shares.addRedeemHandler(newRedeemHandler);

        // Second call should fail
        vm.expectRevert(Shares.Shares__AddRedeemHandler__AlreadyAdded.selector);
        vm.prank(admin);
        shares.addRedeemHandler(newRedeemHandler);
    }

    function test_addRedeemHandler_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");
        address newRedeemHandler = makeAddr("newRedeemHandler");

        vm.expectRevert(Shares.Shares__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        shares.addRedeemHandler(newRedeemHandler);
    }

    function test_addRedeemHandler_success() public {
        address newRedeemHandler = makeAddr("newRedeemHandler");

        vm.expectEmit(address(shares));
        emit Shares.RedeemHandlerAdded(newRedeemHandler);

        vm.prank(admin);
        shares.addRedeemHandler(newRedeemHandler);

        assertTrue(shares.isRedeemHandler(newRedeemHandler));
    }

    function test_removeDepositHandler_fail_alreadyRemoved() public {
        address newDepositHandler = makeAddr("newDepositHandler");

        vm.expectRevert(Shares.Shares__RemoveDepositHandler__AlreadyRemoved.selector);
        vm.prank(admin);
        shares.removeDepositHandler(newDepositHandler);
    }

    function test_removeDepositHandler_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");
        address newDepositHandler = makeAddr("newDepositHandler");

        vm.expectRevert(Shares.Shares__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        shares.removeDepositHandler(newDepositHandler);
    }

    function test_removeDepositHandler_success() public {
        address newDepositHandler = makeAddr("newDepositHandler");

        vm.prank(admin);
        shares.addDepositHandler(newDepositHandler);

        vm.expectEmit(address(shares));
        emit Shares.DepositHandlerRemoved(newDepositHandler);

        vm.prank(admin);
        shares.removeDepositHandler(newDepositHandler);

        assertFalse(shares.isDepositHandler(newDepositHandler));
    }

    function test_removeRedeemHandler_fail_alreadyRemoved() public {
        address newRedeemHandler = makeAddr("newRedeemHandler");

        vm.expectRevert(Shares.Shares__RemoveRedeemHandler__AlreadyRemoved.selector);
        vm.prank(admin);
        shares.removeRedeemHandler(newRedeemHandler);
    }

    function test_removeRedeemHandler_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");
        address newRedeemHandler = makeAddr("newRedeemHandler");

        vm.expectRevert(Shares.Shares__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        shares.removeRedeemHandler(newRedeemHandler);
    }

    function test_removeRedeemHandler_success() public {
        address newRedeemHandler = makeAddr("newRedeemHandler");

        vm.prank(admin);
        shares.addRedeemHandler(newRedeemHandler);

        vm.expectEmit(address(shares));
        emit Shares.RedeemHandlerRemoved(newRedeemHandler);

        vm.prank(admin);
        shares.removeRedeemHandler(newRedeemHandler);

        assertFalse(shares.isRedeemHandler(newRedeemHandler));
    }

    function test_setFeeHandler_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");
        address newFeeHandler = makeAddr("newFeeHandler");

        vm.expectRevert(Shares.Shares__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        shares.setFeeHandler(newFeeHandler);
    }

    function test_setFeeHandler_success() public {
        address newFeeHandler = makeAddr("newFeeHandler");

        vm.expectEmit(address(shares));
        emit Shares.FeeHandlerSet(newFeeHandler);

        vm.prank(admin);
        shares.setFeeHandler(newFeeHandler);

        assertEq(shares.getFeeHandler(), newFeeHandler);
    }

    function test_setSharesTransferValidator_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");
        address newSharesTransferValidator = makeAddr("newSharesTransferValidator");

        vm.expectRevert(Shares.Shares__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        shares.setSharesTransferValidator(newSharesTransferValidator);
    }

    function test_setSharesTransferValidator_success() public {
        address newSharesTransferValidator = makeAddr("newSharesTransferValidator");

        vm.expectEmit(address(shares));
        emit Shares.SharesTransferValidatorSet(newSharesTransferValidator);

        vm.prank(admin);
        shares.setSharesTransferValidator(newSharesTransferValidator);

        assertEq(shares.getSharesTransferValidator(), newSharesTransferValidator);
    }

    function test_setValuationHandler_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");
        address newValuationHandler = makeAddr("newValuationHandler");

        vm.expectRevert(Shares.Shares__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        shares.setValuationHandler(newValuationHandler);
    }

    function test_setValuationHandler_success() public {
        address newValuationHandler = makeAddr("newValuationHandler");

        vm.expectEmit(address(shares));
        emit Shares.ValuationHandlerSet(newValuationHandler);

        vm.prank(admin);
        shares.setValuationHandler(newValuationHandler);

        assertEq(shares.getValuationHandler(), newValuationHandler);
    }

    //==================================================================================================================
    // Valuation
    //==================================================================================================================

    function test_sharePrice_success() public {
        uint256 expectedSharePrice = 123;
        uint256 expectedTimestamp = 456;

        // Set valuation handler
        address valuationHandler = makeAddr("valuationHandler");
        vm.prank(admin);
        shares.setValuationHandler(valuationHandler);

        valuationHandler_mockGetSharePrice({
            _valuationHandler: valuationHandler, _sharePrice: expectedSharePrice, _timestamp: expectedTimestamp
        });

        (uint256 price, uint256 timestamp) = shares.sharePrice();

        assertEq(price, expectedSharePrice);
        assertEq(timestamp, expectedTimestamp);
    }

    function test_shareValue_success() public {
        uint256 expectedSharePrice = 123;
        uint256 expectedTimestamp = 456;

        // Set valuation handler
        address valuationHandler = makeAddr("valuationHandler");
        vm.prank(admin);
        shares.setValuationHandler(valuationHandler);

        valuationHandler_mockGetShareValue({
            _valuationHandler: valuationHandler, _shareValue: expectedSharePrice, _timestamp: expectedTimestamp
        });

        (uint256 price, uint256 timestamp) = shares.shareValue();

        assertEq(price, expectedSharePrice);
        assertEq(timestamp, expectedTimestamp);
    }

    //==================================================================================================================
    // Transfer
    //==================================================================================================================

    function test_transfer_success_noValidator() public {
        __test_transfer_success({_hasValidator: false, _transferFrom: false});
    }

    function test_transfer_success_withValidator() public {
        __test_transfer_success({_hasValidator: true, _transferFrom: false});
    }

    function test_transferFrom_success_noValidator() public {
        __test_transfer_success({_hasValidator: false, _transferFrom: true});
    }

    function test_transferFrom_success_withValidator() public {
        __test_transfer_success({_hasValidator: true, _transferFrom: true});
    }

    function __test_transfer_success(bool _hasValidator, bool _transferFrom) internal {
        address from = makeAddr("__test_transfer:from");
        address to = makeAddr("__test_transfer:to");

        // Give from shares balance to transfer
        uint256 amount = 100;
        deal({token: address(shares), to: from, give: amount, adjust: true});

        // Set an arbitrary transfer validator that will always pass
        if (_hasValidator) {
            address transferValidator = address(new BlankSharesTransferValidator());
            vm.prank(owner);
            shares.setSharesTransferValidator(transferValidator);

            // Pre-assert expected call
            vm.expectCall({
                callee: transferValidator,
                data: abi.encodeWithSelector(ISharesTransferValidator.validateSharesTransfer.selector, from, to, amount)
            });
        }

        if (_transferFrom) {
            // Grant approval to test contract to call transferFrom()
            vm.prank(from);
            shares.approve(address(this), amount);

            shares.transferFrom(from, to, amount);
        } else {
            vm.prank(from);
            shares.transfer(to, amount);
        }

        assertEq(shares.balanceOf(from), 0);
        assertEq(shares.balanceOf(to), amount);
    }

    // NO RULES

    function test_authTransfer_fail_unauthorized() public {
        address randomUser = makeAddr("authTransfer:randomUser");

        vm.expectRevert(Shares.Shares__AuthTransfer__Unauthorized.selector);

        vm.prank(randomUser);
        shares.authTransfer({_to: address(0), _amount: 0});
    }

    function test_authTransfer_success_depositHandler() public {
        address depositHandler = makeAddr("authTransfer:depositHandler");

        vm.prank(owner);
        shares.addDepositHandler(depositHandler);

        __test_authTransfer_success({_from: depositHandler});
    }

    function test_authTransfer_success_redeemHandler() public {
        address redeemHandler = makeAddr("authTransfer:redeemHandler");

        vm.prank(owner);
        shares.addRedeemHandler(redeemHandler);

        __test_authTransfer_success({_from: redeemHandler});
    }

    /// @dev Should not be subject to transfer rules
    function __test_authTransfer_success(address _from) internal {
        address to = makeAddr("authTransfer:to");

        uint256 fromBalance = 100;
        uint256 toBalance = 70;
        uint256 transferAmount = 10;

        // Seed `_from` and `to` with shares
        deal({token: address(shares), to: _from, give: fromBalance, adjust: true});
        deal({token: address(shares), to: to, give: toBalance, adjust: true});

        // Set an arbitrary transfer validator, so that normal transfers would fail
        address transferValidator = makeAddr("transferValidator");
        vm.prank(owner);
        shares.setSharesTransferValidator(transferValidator);

        // Auth transfer `_from` => `to`
        vm.prank(_from);
        shares.authTransfer({_to: to, _amount: transferAmount});

        assertEq(shares.balanceOf(_from), fromBalance - transferAmount);
        assertEq(shares.balanceOf(to), toBalance + transferAmount);
    }

    function test_authTransferFrom_fail_unauthorized() public {
        address randomUser = makeAddr("authTransferFrom:randomUser");

        vm.expectRevert(Shares.Shares__OnlyRedeemHandler__Unauthorized.selector);

        vm.prank(randomUser);
        shares.authTransferFrom({_from: address(0), _to: address(0), _amount: 0});
    }

    /// @dev Should not be subject to transfer rules
    function test_authTransferFrom_success() public {
        address from = makeAddr("authTransfer:from");
        address to = makeAddr("authTransfer:to");

        uint256 fromBalance = 100;
        uint256 toBalance = 70;
        uint256 transferAmount = 10;

        deal({token: address(shares), to: from, give: fromBalance, adjust: true});
        deal({token: address(shares), to: to, give: toBalance, adjust: true});

        // Set an arbitrary transfer validator, so that normal transfers would fail
        address transferValidator = makeAddr("transferValidator");
        vm.prank(owner);
        shares.setSharesTransferValidator(transferValidator);

        // Set a redeem handler to be the caller
        address redeemHandler = makeAddr("redeemHandler");
        vm.prank(owner);
        shares.addRedeemHandler(redeemHandler);

        // Transfer
        vm.prank(redeemHandler);
        shares.authTransferFrom({_from: from, _to: to, _amount: transferAmount});

        assertEq(shares.balanceOf(from), fromBalance - transferAmount);
        assertEq(shares.balanceOf(to), toBalance + transferAmount);
    }

    //==================================================================================================================
    // Shares issuance and asset transfers
    //==================================================================================================================

    function test_mintFor_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(Shares.Shares__OnlyDepositHandler__Unauthorized.selector);

        vm.prank(randomUser);
        shares.mintFor({_to: address(0), _sharesAmount: 0});
    }

    function test_mintFor_success() public {
        uint256 sharesAmount = 100;
        address to = makeAddr("mintFor:to");
        address depositHandler = makeAddr("mintFor:depositHandler");
        vm.prank(owner);
        shares.addDepositHandler(depositHandler);

        vm.prank(depositHandler);
        shares.mintFor({_to: to, _sharesAmount: sharesAmount});

        assertEq(shares.balanceOf(to), sharesAmount);
    }

    function test_burnFor_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(Shares.Shares__OnlyRedeemHandler__Unauthorized.selector);

        vm.prank(randomUser);
        shares.burnFor({_from: address(0), _sharesAmount: 0});
    }

    function test_burnFor_success() public {
        // Mint some shares to `from`
        address from = makeAddr("burnFor:from");
        uint256 initialFromBalance = 100;
        deal({token: address(shares), to: from, give: initialFromBalance, adjust: true});

        uint256 sharesToBurn = initialFromBalance / 5;

        address redeemHandler = makeAddr("burnFor:redeemHandler");
        vm.prank(owner);
        shares.addRedeemHandler(redeemHandler);

        vm.prank(redeemHandler);
        shares.burnFor({_from: from, _sharesAmount: sharesToBurn});

        assertEq(shares.balanceOf(from), initialFromBalance - sharesToBurn);
    }

    function test_withdrawAssetTo_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(Shares.Shares__WithdrawAssetTo__Unauthorized.selector);

        vm.prank(randomUser);
        shares.withdrawAssetTo({_asset: address(0), _to: address(0), _amount: 0});
    }

    function test_withdrawAssetTo_success_fromAdmin() public {
        __test_withdrawAssetTo_success({_caller: admin});
    }

    function test_withdrawAssetTo_success_fromFeeHandler() public {
        address feeHandler = makeAddr("feeHandler");
        vm.prank(owner);
        shares.setFeeHandler(feeHandler);

        __test_withdrawAssetTo_success({_caller: feeHandler});
    }

    function test_withdrawAssetTo_success_fromRedeemHandler() public {
        address redeemHandler = makeAddr("redeemHandler");
        vm.prank(owner);
        shares.addRedeemHandler(redeemHandler);

        __test_withdrawAssetTo_success({_caller: redeemHandler});
    }

    function __test_withdrawAssetTo_success(address _caller) internal {
        MockERC20 mockToken = new MockERC20(18);
        address to = makeAddr("withdrawAssetTo:to");
        uint256 amount = 123;
        uint256 initialBalance = amount * 11;

        // Mint some token to Shares
        mockToken.mintTo(address(shares), initialBalance);

        vm.expectEmit(address(shares));
        emit Shares.AssetWithdrawn({caller: _caller, to: to, asset: address(mockToken), amount: amount});

        vm.prank(_caller);
        shares.withdrawAssetTo({_asset: address(mockToken), _to: to, _amount: amount});

        assertEq(mockToken.balanceOf(address(shares)), initialBalance - amount);
        assertEq(mockToken.balanceOf(to), amount);
    }
}
