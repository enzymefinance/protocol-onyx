// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Script.sol";

/// @notice Encodes a string to bytes10 using SHA256 truncation
/// @dev The encoding algorithm:
///      1. SHA256 hash of the input string
///      2. Hex encode the hash
///      3. Take first 10 characters of the hex string
///      4. Those 10 ASCII characters become the bytes10 value
/// @dev Usage: forge script scripts/EncodeStringToBytes10.s.sol --sig "run(string)" "my_string"
contract EncodeStringToBytes10 is Script {
    bytes private constant HEX_CHARS = "0123456789abcdef";

    function run(string calldata _input) external pure {
        if (bytes(_input).length == 0) {
            console.log("Empty input provided");
            return;
        }

        console.log("Input:", _input);
        bytes10 encodedName = encodeStringToBytes10(_input);
        console.log("Encoded bytes10:");
        console.logBytes10(encodedName);
    }

    /// @notice Encodes a string to bytes10 using SHA256 truncation
    /// @param _input The string to encode
    /// @return encodedName_ The encoded bytes10 value
    function encodeStringToBytes10(string calldata _input) public pure returns (bytes10 encodedName_) {
        // Step 1: SHA256 hash of the input string
        bytes32 hash = sha256(bytes(_input));

        // Step 2: Hex encode the hash
        bytes memory hexString = _bytesToHexString(abi.encodePacked(hash));

        // Step 3: Take first 10 characters
        bytes memory first10 = new bytes(10);
        for (uint256 i = 0; i < 10; i++) {
            first10[i] = hexString[i];
        }

        // Step 4: Convert to bytes10
        return bytes10(first10);
    }

    /// @notice Converts bytes to hex string
    function _bytesToHexString(bytes memory _data) private pure returns (bytes memory hexString_) {
        hexString_ = new bytes(_data.length * 2);

        for (uint256 i = 0; i < _data.length; i++) {
            hexString_[i * 2] = HEX_CHARS[uint8(_data[i] >> 4)];
            hexString_[i * 2 + 1] = HEX_CHARS[uint8(_data[i] & 0x0f)];
        }

        return hexString_;
    }
}
