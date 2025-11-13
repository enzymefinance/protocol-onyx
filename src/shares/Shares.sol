// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ISharesTransferValidator} from "src/interfaces/ISharesTransferValidator.sol";
import {IValuationHandler} from "src/interfaces/IValuationHandler.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";

/// @title Shares Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Shares token with registries and issuance-related logic
/// @dev The core-most contract.
/// Security notes:
/// - there are no built-in protections against:
///   - a very low totalSupply() (e.g., "inflation attack")
///   - a very low share value
contract Shares is ERC20Upgradeable, Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;

    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 private constant SHARES_STORAGE_LOCATION =
        0xbe724a55f726228f14b884d45d89388bc2a03793a0006937116ea1275a51fb00;
    string private constant SHARES_STORAGE_LOCATION_ID = "Shares";

    /// @custom:storage-location erc7201:enzyme.Shares
    /// @param valueAsset A representation of the asset of account in which core values are reported (e.g., USD)
    /// @param feeHandler The contract that handles fees (settlement, claims, accounting)
    /// @param sharesTransferValidator A contract that supplies shares transfer validation
    /// @param valuationHandler The contract that handles valuation-related operations
    /// @param isDepositHandler True if the account is an allowed deposit handler
    /// @param isRedeemHandler True if the account is an allowed redeem handler
    /// @param isAdmin True if the account is an admin
    /// @dev `valueAsset` is not used within the system, but is stored on-chain in case needed by integrators.
    struct SharesStorage {
        bytes32 valueAsset;
        address feeHandler;
        address sharesTransferValidator;
        address valuationHandler;
        mapping(address => bool) isDepositHandler;
        mapping(address => bool) isRedeemHandler;
        mapping(address => bool) isAdmin;
    }

    function __getSharesStorage() private pure returns (SharesStorage storage $) {
        bytes32 location = SHARES_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event AdminAdded(address admin);

    event AdminRemoved(address admin);

    event AssetWithdrawn(address caller, address asset, address to, uint256 amount);

    event DepositHandlerAdded(address depositHandler);

    event DepositHandlerRemoved(address depositHandler);

    event FeeHandlerSet(address feeHandler);

    event RedeemHandlerAdded(address redeemHandler);

    event RedeemHandlerRemoved(address redeemHandler);

    event SharesTransferValidatorSet(address validator);

    event ValuationHandlerSet(address valuationHandler);

    event ValueAssetSet(bytes32 valueAsset);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error Shares__AddAdmin__AlreadyAdded();

    error Shares__AddAllowedHolder__AlreadyAdded();

    error Shares__AddDepositHandler__AlreadyAdded();

    error Shares__AddRedeemHandler__AlreadyAdded();

    error Shares__AuthTransfer__Unauthorized();

    error Shares__GetDepositAssetsDest__NotSet();

    error Shares__Init__EmptyName();

    error Shares__Init__EmptySymbol();

    error Shares__OnlyAdminOrOwner__Unauthorized();

    error Shares__OnlyDepositHandler__Unauthorized();

    error Shares__OnlyFeeHandler__Unauthorized();

    error Shares__OnlyRedeemHandler__Unauthorized();

    error Shares__RemoveAdmin__AlreadyRemoved();

    error Shares__RemoveAllowedHolder__AlreadyRemoved();

    error Shares__RemoveDepositHandler__AlreadyRemoved();

    error Shares__RemoveRedeemHandler__AlreadyRemoved();

    error Shares__SetValueAsset__Empty();

    error Shares__ValidateTransferRecipient__NotAllowed();

    error Shares__WithdrawAssetTo__Unauthorized();

    //==================================================================================================================
    // Modifiers
    //==================================================================================================================

    modifier onlyAdminOrOwner() {
        require(isAdminOrOwner(msg.sender), Shares__OnlyAdminOrOwner__Unauthorized());

        _;
    }

    modifier onlyDepositHandler() {
        require(isDepositHandler(msg.sender), Shares__OnlyDepositHandler__Unauthorized());

        _;
    }

    modifier onlyFeeHandler() {
        require(msg.sender == getFeeHandler(), Shares__OnlyFeeHandler__Unauthorized());

        _;
    }

    modifier onlyRedeemHandler() {
        require(isRedeemHandler(msg.sender), Shares__OnlyRedeemHandler__Unauthorized());

        _;
    }

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: SHARES_STORAGE_LOCATION, _id: SHARES_STORAGE_LOCATION_ID
        });
    }

    //==================================================================================================================
    // Initialize
    //==================================================================================================================

    /// @notice Initializer for the contract
    /// @param _owner The account to be the "owner" role
    /// @param _name The name of the Shares token (ERC20)
    /// @param _symbol The symbol of the Shares token (ERC20)
    /// @param _valueAsset The representation of the asset of account for valuations (e.g., USD)
    function init(address _owner, string memory _name, string memory _symbol, bytes32 _valueAsset)
        external
        initializer
    {
        require(bytes(_name).length > 0, Shares__Init__EmptyName());
        require(bytes(_symbol).length > 0, Shares__Init__EmptySymbol());

        __ERC20_init({name_: _name, symbol_: _symbol});
        __Ownable_init({initialOwner: _owner});

        __setValueAsset(_valueAsset);
    }

    //==================================================================================================================
    // ERC20 overrides
    //==================================================================================================================

    /// @notice Standard ERC20 transfer of shares
    function transfer(address _to, uint256 _amount) public override returns (bool) {
        __validateSharesTransfer({_from: msg.sender, _to: _to, _amount: _amount});

        return super.transfer(_to, _amount);
    }

    /// @notice Standard ERC20 transferFrom of shares
    function transferFrom(address _from, address _to, uint256 _amount) public override returns (bool) {
        __validateSharesTransfer({_from: _from, _to: _to, _amount: _amount});

        return super.transferFrom(_from, _to, _amount);
    }

    function __validateSharesTransfer(address _from, address _to, uint256 _amount) internal {
        address sharesTransferValidator = getSharesTransferValidator();

        if (sharesTransferValidator != address(0)) {
            ISharesTransferValidator(sharesTransferValidator)
                .validateSharesTransfer({_from: _from, _to: _to, _amount: _amount});
        }
    }

    //==================================================================================================================
    // ERC20-like extensions (access: mixed)
    //==================================================================================================================

    /// @notice Unvalidated transfer() for trusted handlers.
    /// @dev Any validation of the recipient must be done by the calling contract.
    /// Needed for, e.g.,:
    /// - Shares distribution from async deposit handler
    /// - Redeem request cancellation from async redeem handler
    function authTransfer(address _to, uint256 _amount) external {
        require(isDepositHandler(msg.sender) || isRedeemHandler(msg.sender), Shares__AuthTransfer__Unauthorized());

        _transfer(msg.sender, _to, _amount);
    }

    /// @notice Unvalidated transferFrom() for trusted handlers.
    /// @dev Any validation of the recipient must be done by the calling contract.
    /// Needed for, e.g.,:
    /// - Approval-less redemption from async redeem handler
    /// - Forced transfers via redeem handler (sometimes a compliance requirement)
    function authTransferFrom(address _from, address _to, uint256 _amount) external onlyRedeemHandler {
        _transfer(_from, _to, _amount);
    }

    //==================================================================================================================
    // Config (access: owner)
    //==================================================================================================================

    function addAdmin(address _admin) external onlyOwner {
        require(!isAdmin(_admin), Shares__AddAdmin__AlreadyAdded());

        SharesStorage storage $ = __getSharesStorage();
        $.isAdmin[_admin] = true;

        emit AdminAdded(_admin);
    }

    function removeAdmin(address _admin) external onlyOwner {
        require(isAdmin(_admin), Shares__RemoveAdmin__AlreadyRemoved());

        SharesStorage storage $ = __getSharesStorage();
        $.isAdmin[_admin] = false;

        emit AdminRemoved(_admin);
    }

    //==================================================================================================================
    // Config (access: admin or owner)
    //==================================================================================================================

    // SYSTEM CONTRACTS

    function addDepositHandler(address _handler) external onlyAdminOrOwner {
        require(!isDepositHandler(_handler), Shares__AddDepositHandler__AlreadyAdded());

        SharesStorage storage $ = __getSharesStorage();
        $.isDepositHandler[_handler] = true;

        emit DepositHandlerAdded(_handler);
    }

    function addRedeemHandler(address _handler) external onlyAdminOrOwner {
        require(!isRedeemHandler(_handler), Shares__AddRedeemHandler__AlreadyAdded());

        SharesStorage storage $ = __getSharesStorage();
        $.isRedeemHandler[_handler] = true;

        emit RedeemHandlerAdded(_handler);
    }

    function removeDepositHandler(address _handler) external onlyAdminOrOwner {
        require(isDepositHandler(_handler), Shares__RemoveDepositHandler__AlreadyRemoved());

        SharesStorage storage $ = __getSharesStorage();
        $.isDepositHandler[_handler] = false;

        emit DepositHandlerRemoved(_handler);
    }

    function removeRedeemHandler(address _handler) external onlyAdminOrOwner {
        require(isRedeemHandler(_handler), Shares__RemoveRedeemHandler__AlreadyRemoved());

        SharesStorage storage $ = __getSharesStorage();
        $.isRedeemHandler[_handler] = false;

        emit RedeemHandlerRemoved(_handler);
    }

    function setFeeHandler(address _feeHandler) external onlyAdminOrOwner {
        SharesStorage storage $ = __getSharesStorage();
        $.feeHandler = _feeHandler;

        emit FeeHandlerSet(_feeHandler);
    }

    /// @dev Can set to any non-existent, arbitrary address to make Shares non-transferrable
    function setSharesTransferValidator(address _sharesTransferValidator) external onlyAdminOrOwner {
        SharesStorage storage $ = __getSharesStorage();
        $.sharesTransferValidator = _sharesTransferValidator;

        emit SharesTransferValidatorSet(_sharesTransferValidator);
    }

    function setValuationHandler(address _valuationHandler) external onlyAdminOrOwner {
        SharesStorage storage $ = __getSharesStorage();
        $.valuationHandler = _valuationHandler;

        emit ValuationHandlerSet(_valuationHandler);
    }

    // HELPERS

    function __setValueAsset(bytes32 _valueAsset) internal {
        require(_valueAsset != "", Shares__SetValueAsset__Empty());

        SharesStorage storage $ = __getSharesStorage();
        $.valueAsset = _valueAsset;

        emit ValueAssetSet(_valueAsset);
    }

    //==================================================================================================================
    // Valuation
    //==================================================================================================================

    /// @notice Returns the latest share price and its timestamp
    /// @return price_ The share price
    /// @return timestamp_ The timestamp of the share price
    /// @dev 18-decimals of precision
    function sharePrice() external view returns (uint256 price_, uint256 timestamp_) {
        return IValuationHandler(getValuationHandler()).getSharePrice();
    }

    /// @notice Returns the latest share value and its timestamp
    /// @return value_ The share value
    /// @return timestamp_ The timestamp of the share value
    /// @dev 18-decimals of precision
    function shareValue() external view returns (uint256 value_, uint256 timestamp_) {
        return IValuationHandler(getValuationHandler()).getShareValue();
    }

    //==================================================================================================================
    // Shares issuance and asset transfers
    //==================================================================================================================

    /// @dev No general burn() function is exposed, in order to guarantee constant supply during share value updates

    // DEPOSIT FLOW

    /// @dev Callable by: DepositHandler
    function mintFor(address _to, uint256 _sharesAmount) external onlyDepositHandler {
        _mint(_to, _sharesAmount);
    }

    // REDEEM FLOW

    /// @dev Callable by: RedeemHandler
    function burnFor(address _from, uint256 _sharesAmount) external onlyRedeemHandler {
        _burn(_from, _sharesAmount);
    }

    // ASSET TRANSFERS

    /// @dev Callable by: admin, RedeemHandler, FeeHandler
    function withdrawAssetTo(address _asset, address _to, uint256 _amount) external {
        require(
            isAdminOrOwner(msg.sender) || isRedeemHandler(msg.sender) || msg.sender == getFeeHandler(),
            Shares__WithdrawAssetTo__Unauthorized()
        );

        IERC20(_asset).safeTransfer(_to, _amount);

        emit AssetWithdrawn({caller: msg.sender, asset: _asset, to: _to, amount: _amount});
    }

    //==================================================================================================================
    // Misc
    //==================================================================================================================

    /// @notice Returns whether an account has either an "admin" or "owner" role
    function isAdminOrOwner(address _who) public view returns (bool) {
        return _who == owner() || isAdmin(_who);
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    /// @notice Returns the contract that handles fees logic
    function getFeeHandler() public view returns (address) {
        return __getSharesStorage().feeHandler;
    }

    /// @notice Returns the contract that validates shares transfers
    function getSharesTransferValidator() public view returns (address) {
        return __getSharesStorage().sharesTransferValidator;
    }

    /// @notice Returns the contract the handles valuation logic
    function getValuationHandler() public view returns (address) {
        return __getSharesStorage().valuationHandler;
    }

    /// @notice Returns the encoded representation of the asset of account (e.g., USD, ETH)
    function getValueAsset() public view returns (bytes32) {
        return __getSharesStorage().valueAsset;
    }

    /// @notice Returns whether an account has an "admin" role
    function isAdmin(address _who) public view returns (bool) {
        return __getSharesStorage().isAdmin[_who];
    }

    /// @notice Returns whether an account is an allowed deposit handler
    function isDepositHandler(address _who) public view returns (bool) {
        return __getSharesStorage().isDepositHandler[_who];
    }

    /// @notice Returns whether an account is an allowed redeem handler
    function isRedeemHandler(address _who) public view returns (bool) {
        return __getSharesStorage().isRedeemHandler[_who];
    }
}
