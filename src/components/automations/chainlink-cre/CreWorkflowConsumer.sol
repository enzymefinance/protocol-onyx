// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {LimitedAccessLimitedCallForwarder} from "src/components/roles/LimitedAccessLimitedCallForwarder.sol";
import {OpenAccessLimitedCallForwarder} from "src/components/roles/OpenAccessLimitedCallForwarder.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";
import {IReceiver} from "./IReceiver.sol";

/// @title CreWorkflowConsumer Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A contract that receives and processes Chainlink Runtime Environment (CRE) reports
/// @dev The workflowId and workflowName checks
/// serve as defense-in-depth against accidents (e.g., the owner misconfiguring a workflow registration)
/// or off-chain compromises (e.g., if the workflow owner's off-chain registration credentials were
/// compromised, the on-chain checks would still block unauthorized workflows from executing).
contract CreWorkflowConsumer is IReceiver, ComponentHelpersMixin {
    //==================================================================================================================
    // Immutables
    //==================================================================================================================

    address public immutable ALLOWED_WORKFLOW_OWNER;
    address public immutable CHAINLINK_KEYSTONE_FORWARDER;

    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 public constant CRE_WORKFLOW_CONSUMER_STORAGE_LOCATION =
        0x0e3fe8355c10db856bcbccfa41da7cfb4d5b6dd681a069e0ed1b68eddbef9600;
    string public constant CRE_WORKFLOW_CONSUMER_STORAGE_LOCATION_ID = "CreWorkflowConsumer";

    /// @custom:storage-location erc7201:enzyme.CreWorkflowConsumer
    /// @param allowedWorkflowId The allowed workflow ID
    /// @param allowedWorkflowName The allowed workflow name
    /// @param limitedAccessLimitedCallForwarder The forwarder contract for executing calls
    struct CreWorkflowConsumerStorage {
        bytes32 allowedWorkflowId;
        bytes10 allowedWorkflowName;
        LimitedAccessLimitedCallForwarder limitedAccessLimitedCallForwarder;
    }

    function __getCreWorkflowConsumerStorage() internal pure returns (CreWorkflowConsumerStorage storage $) {
        bytes32 location = CRE_WORKFLOW_CONSUMER_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event AllowedWorkflowIdSet(bytes32 allowedWorkflowId);

    event AllowedWorkflowNameSet(bytes10 allowedWorkflowName);

    event LimitedAccessLimitedCallForwarderSet(LimitedAccessLimitedCallForwarder limitedAccessLimitedCallForwarder);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error CreWorkflowConsumer__Init__AlreadyInitialized();

    error CreWorkflowConsumer__Init__EmptyLimitedAccessLimitedCallForwarder();

    error CreWorkflowConsumer__OnReport__InvalidOnReportSender();

    error CreWorkflowConsumer__OnReport__InvalidWorkflowId();

    error CreWorkflowConsumer__OnReport__InvalidWorkflowName();

    error CreWorkflowConsumer__OnReport__InvalidWorkflowOwner();

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor(address _chainlinkKeystoneForwarder, address _allowedWorkflowOwner) {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: CRE_WORKFLOW_CONSUMER_STORAGE_LOCATION, _id: CRE_WORKFLOW_CONSUMER_STORAGE_LOCATION_ID
        });
        CHAINLINK_KEYSTONE_FORWARDER = _chainlinkKeystoneForwarder;
        ALLOWED_WORKFLOW_OWNER = _allowedWorkflowOwner;
    }

    //==================================================================================================================
    // Initialize
    //==================================================================================================================

    /// @notice Initializes the contract with the allowed workflow name and forwarder
    /// @param _allowedWorkflowName The workflow name to allow
    /// @param _limitedAccessLimitedCallForwarder The forwarder contract to use
    function init(bytes10 _allowedWorkflowName, LimitedAccessLimitedCallForwarder _limitedAccessLimitedCallForwarder)
        external
    {
        require(!__isInitialized(), CreWorkflowConsumer__Init__AlreadyInitialized());
        require(
            address(_limitedAccessLimitedCallForwarder) != address(0),
            CreWorkflowConsumer__Init__EmptyLimitedAccessLimitedCallForwarder()
        );

        CreWorkflowConsumerStorage storage $ = __getCreWorkflowConsumerStorage();
        $.allowedWorkflowName = _allowedWorkflowName;
        $.limitedAccessLimitedCallForwarder = _limitedAccessLimitedCallForwarder;

        emit AllowedWorkflowNameSet(_allowedWorkflowName);
        emit LimitedAccessLimitedCallForwarderSet(_limitedAccessLimitedCallForwarder);
    }

    function __isInitialized() internal view returns (bool) {
        return address(getLimitedAccessLimitedCallForwarder()) != address(0);
    }

    //==================================================================================================================
    // Workflow execution
    //==================================================================================================================

    /// @notice Receives and processes a report from the Chainlink workflow
    /// @param _metadata The metadata containing workflow ID, name, and owner
    /// @param _report The encoded calls to execute
    function onReport(bytes calldata _metadata, bytes calldata _report) external {
        require(msg.sender == CHAINLINK_KEYSTONE_FORWARDER, CreWorkflowConsumer__OnReport__InvalidOnReportSender());

        (bytes32 workflowId, bytes10 workflowName, address workflowOwner) = __decodeMetadata(_metadata);

        require(workflowId == getAllowedWorkflowId(), CreWorkflowConsumer__OnReport__InvalidWorkflowId());
        require(workflowName == getAllowedWorkflowName(), CreWorkflowConsumer__OnReport__InvalidWorkflowName());
        require(workflowOwner == ALLOWED_WORKFLOW_OWNER, CreWorkflowConsumer__OnReport__InvalidWorkflowOwner());

        getLimitedAccessLimitedCallForwarder()
            .executeCalls({_calls: abi.decode(_report, (OpenAccessLimitedCallForwarder.Call[]))});
    }

    /// @notice Checks if the contract supports a given interface
    /// @param _interfaceId The interface ID to check
    /// @return supported_ True if the interface is supported
    function supportsInterface(bytes4 _interfaceId) public pure virtual override returns (bool supported_) {
        return _interfaceId == type(IReceiver).interfaceId || _interfaceId == type(IERC165).interfaceId;
    }

    //==================================================================================================================
    // Value updates (access: admin or owner)
    //==================================================================================================================

    /// @notice Sets the allowed workflow ID
    /// @param _allowedWorkflowId The workflow ID to allow
    function setAllowedWorkflowId(bytes32 _allowedWorkflowId) external onlyAdminOrOwner {
        __getCreWorkflowConsumerStorage().allowedWorkflowId = _allowedWorkflowId;

        emit AllowedWorkflowIdSet(_allowedWorkflowId);
    }

    //==================================================================================================================
    // Helper functions
    //==================================================================================================================

    /// @dev Decodes the metadata from a Chainlink workflow report
    function __decodeMetadata(bytes memory _metadata)
        private
        pure
        returns (bytes32 workflowId_, bytes10 workflowName_, address workflowOwner_)
    {
        // Metadata structure:
        // - First 32 bytes: length of the byte array (standard for dynamic bytes)
        // - Offset 32, size 32: workflow_id (bytes32)
        // - Offset 64, size 10: workflow_name (bytes10)
        // - Offset 74, size 20: workflow_owner (address)
        assembly {
            workflowId_ := mload(add(_metadata, 32))
            workflowName_ := mload(add(_metadata, 64))
            workflowOwner_ := shr(mul(12, 8), mload(add(_metadata, 74)))
        }
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    function getAllowedWorkflowId() public view returns (bytes32 allowedWorkflowId_) {
        return __getCreWorkflowConsumerStorage().allowedWorkflowId;
    }

    function getAllowedWorkflowName() public view returns (bytes10 allowedWorkflowName_) {
        return __getCreWorkflowConsumerStorage().allowedWorkflowName;
    }

    function getLimitedAccessLimitedCallForwarder()
        public
        view
        returns (LimitedAccessLimitedCallForwarder limitedAccessLimitedCallForwarder_)
    {
        return __getCreWorkflowConsumerStorage().limitedAccessLimitedCallForwarder;
    }
}
