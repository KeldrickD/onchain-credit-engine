// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title SignatureVerifier
/// @notice EIP-712 typed structured data verification for RiskPayload
/// @dev Designed for semi-trusted oracle with upgrade path to decentralized
library SignatureVerifier {
    // EIP-712 typehash for RiskPayload
    // RiskPayload(address user,uint256 score,uint256 riskTier,uint256 timestamp,uint256 nonce)
    bytes32 internal constant RISK_PAYLOAD_TYPEHASH =
        keccak256(
            "RiskPayload(address user,uint256 score,uint256 riskTier,uint256 timestamp,uint256 nonce)"
        );

    // EIP-712 Domain typehash
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

    /// @notice Computes the EIP-712 domain separator
    /// @param name Contract name for domain
    /// @param version Contract version for domain
    /// @param verifyingContract Address of the contract verifying signatures
    function domainSeparator(
        string memory name,
        string memory version,
        address verifyingContract
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    EIP712_DOMAIN_TYPEHASH,
                    keccak256(bytes(name)),
                    keccak256(bytes(version)),
                    block.chainid,
                    verifyingContract
                )
            );
    }

    /// @notice Computes the struct hash for a RiskPayload
    /// @param user Wallet address being scored
    /// @param score Credit score (0-1000)
    /// @param riskTier Risk tier classification
    /// @param timestamp Unix timestamp when payload was signed
    /// @param nonce Unique nonce for replay protection
    function hashRiskPayload(
        address user,
        uint256 score,
        uint256 riskTier,
        uint256 timestamp,
        uint256 nonce
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(RISK_PAYLOAD_TYPEHASH, user, score, riskTier, timestamp, nonce)
            );
    }

    /// @notice Computes the EIP-712 digest for signing
    /// @param domainSeparator_ The EIP-712 domain separator
    /// @param structHash The hash of the typed data struct
    function toTypedDataHash(bytes32 domainSeparator_, bytes32 structHash)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator_, structHash));
    }

    /// @notice Recovers the signer address from an EIP-712 signature
    /// @param digest The EIP-712 digest (hash of "\x19\x01" || domainSeparator || structHash)
    /// @param signature 65-byte signature (r, s, v)
    /// @return signer The address that signed the digest
    function recover(bytes32 digest, bytes calldata signature)
        internal
        pure
        returns (address signer)
    {
        require(signature.length == 65, "SignatureVerifier: invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        // EIP-2: allow signature with v=0 and v=1, adjust to 27/28
        if (v < 27) {
            v += 27;
        }
        require(v == 27 || v == 28, "SignatureVerifier: invalid v");

        signer = ecrecover(digest, v, r, s);
        require(signer != address(0), "SignatureVerifier: invalid signature");
    }
}
