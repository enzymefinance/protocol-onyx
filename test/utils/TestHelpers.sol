// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IFeeHandler} from "src/interfaces/IFeeHandler.sol";
import {IPositionTracker} from "src/components/value/position-trackers/IPositionTracker.sol";
import {IValuationHandler} from "src/interfaces/IValuationHandler.sol";
import {Shares} from "src/shares/Shares.sol";

import {BlankFeeHandler, BlankPositionTracker} from "test/mocks/Blanks.sol";

contract TestHelpers is Test {
    function createShares() internal returns (Shares shares_) {
        address owner = makeAddr("owner");
        string memory name = "Test Shares";
        string memory symbol = "TST";
        bytes32 valueAsset = keccak256("USD");

        shares_ = new Shares();
        shares_.init({_owner: owner, _name: name, _symbol: symbol, _valueAsset: valueAsset});
    }

    // MOCKS: FUNCTION CALLS

    function feeHandler_mockGetTotalValueOwed(address _feeHandler, uint256 _totalValueOwed) internal {
        vm.mockCall(_feeHandler, IFeeHandler.getTotalValueOwed.selector, abi.encode(_totalValueOwed));
    }

    function feeHandler_mockSettleEntranceFeeGivenGrossShares(address _feeHandler, uint256 _feeSharesAmount) internal {
        vm.mockCall(_feeHandler, IFeeHandler.settleEntranceFeeGivenGrossShares.selector, abi.encode(_feeSharesAmount));
    }

    function feeHandler_mockSettleEntranceFeeGivenGrossShares(
        address _feeHandler,
        uint256 _feeSharesAmount,
        uint256 _grossSharesAmount
    ) internal {
        vm.mockCall(
            _feeHandler,
            abi.encodeWithSelector(IFeeHandler.settleEntranceFeeGivenGrossShares.selector, _grossSharesAmount),
            abi.encode(_feeSharesAmount)
        );
    }

    function feeHandler_mockSettleExitFeeGivenGrossShares(address _feeHandler, uint256 _feeSharesAmount) internal {
        vm.mockCall(_feeHandler, IFeeHandler.settleExitFeeGivenGrossShares.selector, abi.encode(_feeSharesAmount));
    }

    function feeHandler_mockSettleExitFeeGivenGrossShares(
        address _feeHandler,
        uint256 _feeSharesAmount,
        uint256 _grossSharesAmount
    ) internal {
        vm.mockCall(
            _feeHandler,
            abi.encodeWithSelector(IFeeHandler.settleExitFeeGivenGrossShares.selector, _grossSharesAmount),
            abi.encode(_feeSharesAmount)
        );
    }

    function positionTracker_mockGetPositionValue(address _positionTracker, int256 _value) internal {
        vm.mockCall(_positionTracker, IPositionTracker.getPositionValue.selector, abi.encode(_value));
    }

    function valuationHandler_mockGetDefaultSharePrice(address _valuationHandler, uint256 _defaultSharePrice) internal {
        vm.mockCall(_valuationHandler, IValuationHandler.getDefaultSharePrice.selector, abi.encode(_defaultSharePrice));
    }

    function valuationHandler_mockGetSharePrice(address _valuationHandler, uint256 _sharePrice, uint256 _timestamp)
        internal
    {
        vm.mockCall(_valuationHandler, IValuationHandler.getSharePrice.selector, abi.encode(_sharePrice, _timestamp));
    }

    function valuationHandler_mockGetShareValue(address _valuationHandler, uint256 _shareValue, uint256 _timestamp)
        internal
    {
        vm.mockCall(_valuationHandler, IValuationHandler.getShareValue.selector, abi.encode(_shareValue, _timestamp));
    }

    function shares_mockSharePrice(address _shares, uint256 _sharePrice, uint256 _timestamp) internal {
        vm.mockCall(_shares, Shares.sharePrice.selector, abi.encode(_sharePrice, _timestamp));
    }

    // MOCKS: CONTRACTS

    function setMockFeeHandler(address _shares, uint256 _totalValueOwed) internal returns (address feeHandler_) {
        feeHandler_ = address(new BlankFeeHandler());

        vm.prank(Shares(_shares).owner());
        Shares(_shares).setFeeHandler(feeHandler_);

        feeHandler_mockGetTotalValueOwed({_feeHandler: feeHandler_, _totalValueOwed: _totalValueOwed});
    }

    // MISC

    function increaseSharesSupply(address _shares, uint256 _increaseAmount) internal {
        // Mint shares to create desired supply
        address mintTo = makeAddr("increaseSharesSupply:mintTo");
        deal({token: _shares, to: mintTo, give: _increaseAmount, adjust: true});
    }
}
