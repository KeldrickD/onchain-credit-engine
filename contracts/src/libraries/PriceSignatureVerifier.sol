// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library PriceSignatureVerifier {
    bytes32 internal constant PRICE_PAYLOAD_TYPEHASH =
        keccak256(
            "PricePayload(address asset,uint256 price,uint256 timestamp,uint256 nonce)"
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

    function hashPricePayload(
        address asset,
        uint256 price,
        uint256 timestamp,
        uint256 nonce
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(PRICE_PAYLOAD_TYPEHASH, asset, price, timestamp, nonce));
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
        require(signature.length == 65, "PriceSignatureVerifier: invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        if (v < 27) v += 27;
        require(v == 27 || v == 28, "PriceSignatureVerifier: invalid v");

        signer = ecrecover(digest, v, r, s);
        require(signer != address(0), "PriceSignatureVerifier: invalid signature");
    }
}
