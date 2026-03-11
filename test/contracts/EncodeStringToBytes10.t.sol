// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {EncodeStringToBytes10} from "scripts/EncodeStringToBytes10.s.sol";

contract EncodeStringToBytes10Test is Test {
    EncodeStringToBytes10 encoder;

    function setUp() public {
        encoder = new EncodeStringToBytes10();
    }

    function test_encodeStringToBytes10_success_knownValue() public view {
        // SHA256("test") = 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08
        // First 10 hex chars: "9f86d08188"
        // As bytes10: 0x39663836643038313838 (ASCII codes of "9f86d08188")
        string memory input = "test";
        bytes10 expected = bytes10("9f86d08188");

        bytes10 result = encoder.encodeStringToBytes10(input);

        assertEq(result, expected, "Encoding 'test' should produce expected bytes10");
    }

    function test_encodeStringToBytes10_success_longString() public view {
        // SHA256("this_is_a_very_long_string_that_exceeds_normal_length_requirements") = 1b8044f3a4e1e6ac1af11b34a2d5537c72e2e5ba09f4914ee1322a811bbf59c5
        // First 10 hex chars: "1b8044f3a4"
        string memory input = "this_is_a_very_long_string_that_exceeds_normal_length_requirements";
        bytes10 expected = bytes10("1b8044f3a4");

        bytes10 result = encoder.encodeStringToBytes10(input);

        assertEq(result, expected, "Long string should produce expected bytes10");
    }

    function test_encodeStringToBytes10_success_deterministicOutput() public view {
        string memory input = "deterministic_test";

        bytes10 result1 = encoder.encodeStringToBytes10(input);
        bytes10 result2 = encoder.encodeStringToBytes10(input);

        assertEq(result1, result2, "Same input should always produce same output");
    }

    function test_encodeStringToBytes10_success_differentInputsProduceDifferentOutputs() public view {
        string memory input1 = "input_one";
        string memory input2 = "input_two";

        bytes10 result1 = encoder.encodeStringToBytes10(input1);
        bytes10 result2 = encoder.encodeStringToBytes10(input2);

        assertTrue(result1 != result2, "Different inputs should produce different outputs");
    }

    function test_encodeStringToBytes10_success_emptyString() public view {
        // SHA256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        // First 10 hex chars: "e3b0c44298"
        string memory input = "";
        bytes10 expected = bytes10("e3b0c44298");

        bytes10 result = encoder.encodeStringToBytes10(input);

        assertEq(result, expected, "Encoding empty string should produce expected bytes10");
    }
}
