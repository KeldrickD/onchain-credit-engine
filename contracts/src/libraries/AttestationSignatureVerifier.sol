// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AttestationSignatureVerifier
/// @notice EIP-712 verification for Attestation payloads
library AttestationSignatureVerifier {
    bytes32 internal constant ATTESTATION_TYPEHASH =
        keccak256(
            "Attestation(address subject,bytes32 attestationType,bytes32 dataHash,bytes32 data,string uri,uint64 issuedAt,uint64 expiresAt,uint64 nonce)"
        );
    bytes32 internal constant SUBJECT_ATTESTATION_TYPEHASH =
        keccak256(
            "SubjectAttestation(bytes32 subjectId,bytes32 attestationType,bytes32 dataHash,bytes32 data,string uri,uint64 issuedAt,uint64 expiresAt,uint64 nonce)"
        );

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

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

    function hashAttestation(
        address subject,
        bytes32 attestationType,
        bytes32 dataHash,
        bytes32 data,
        string calldata uri,
        uint64 issuedAt,
        uint64 expiresAt,
        uint64 nonce
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    ATTESTATION_TYPEHASH,
                    subject,
                    attestationType,
                    dataHash,
                    data,
                    keccak256(bytes(uri)),
                    issuedAt,
                    expiresAt,
                    nonce
                )
            );
    }

    function hashSubjectAttestation(
        bytes32 subjectId,
        bytes32 attestationType,
        bytes32 dataHash,
        bytes32 data,
        string calldata uri,
        uint64 issuedAt,
        uint64 expiresAt,
        uint64 nonce
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    SUBJECT_ATTESTATION_TYPEHASH,
                    subjectId,
                    attestationType,
                    dataHash,
                    data,
                    keccak256(bytes(uri)),
                    issuedAt,
                    expiresAt,
                    nonce
                )
            );
    }

    function toTypedDataHash(bytes32 domainSeparator_, bytes32 structHash)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator_, structHash));
    }

    function recover(bytes32 digest, bytes calldata signature)
        internal
        pure
        returns (address signer)
    {
        require(signature.length == 65, "AttestationVerifier: invalid sig length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        if (v < 27) v += 27;
        require(v == 27 || v == 28, "AttestationVerifier: invalid v");

        signer = ecrecover(digest, v, r, s);
        require(signer != address(0), "AttestationVerifier: invalid signature");
    }
}
