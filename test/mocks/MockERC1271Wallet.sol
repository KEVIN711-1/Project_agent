// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @notice Contract wallet that accepts EIP-712 digests signed by a fixed EOA (`signingAddress`).
contract MockERC1271Wallet is IERC1271 {
    address public immutable signingAddress;

    constructor(address signingAddress_) {
        signingAddress = signingAddress_;
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue) {
        address recovered = ECDSA.recover(hash, signature);
        if (recovered == signingAddress) {
            return IERC1271.isValidSignature.selector;
        }
        return 0xffffffff;
    }
}
