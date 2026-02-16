// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {PriceSignatureVerifier} from "./libraries/PriceSignatureVerifier.sol";

/// @title SignedPriceOracle
/// @notice EIP-712 signed price feed. Stores latest price per asset on verification.
contract SignedPriceOracle is IPriceOracle {
    string public constant DOMAIN_NAME = "OCX Price Oracle";
    string public constant DOMAIN_VERSION = "1";
    uint256 public constant PAYLOAD_VALIDITY_WINDOW = 300;

    address public immutable oracleSigner;

    /// @notice Next nonce per asset (sequential, prevents replay)
    mapping(address => uint256) public nextNonce;

    mapping(bytes32 => bool) public usedNonces;
    mapping(address => uint256) private _price;
    mapping(address => uint256) private _lastUpdated;

    event PriceUpdated(address indexed asset, uint256 price);

    error SignedPriceOracle_InvalidSignature();
    error SignedPriceOracle_ExpiredTimestamp();
    error SignedPriceOracle_ReplayAttack();

    constructor(address _oracleSigner) {
        oracleSigner = _oracleSigner;
    }

    function verifyPricePayload(PricePayload calldata payload, bytes calldata signature)
        external
        override
        returns (bool)
    {
        _validateAndConsume(payload, signature);
        _price[payload.asset] = payload.price;
        _lastUpdated[payload.asset] = block.timestamp;
        emit PriceUpdated(payload.asset, payload.price);
        return true;
    }

    function verifyPricePayloadView(PricePayload calldata payload, bytes calldata signature)
        external
        view
        override
        returns (bool)
    {
        return _verify(payload, signature);
    }

    function getPrice(address asset) external view override returns (uint256 price, uint256 lastUpdated) {
        return (_price[asset], _lastUpdated[asset]);
    }

    /// @notice Checks if a nonce has been consumed for an asset
    function isNonceUsed(address asset, uint256 nonce) external view returns (bool) {
        return usedNonces[_nonceKey(asset, nonce)];
    }

    function getPricePayloadDigest(PricePayload calldata payload) external view returns (bytes32) {
        bytes32 structHash =
            PriceSignatureVerifier.hashPricePayload(
                payload.asset,
                payload.price,
                payload.timestamp,
                payload.nonce
            );
        return
            PriceSignatureVerifier.toTypedDataHash(
                PriceSignatureVerifier.domainSeparator(DOMAIN_NAME, DOMAIN_VERSION, address(this)),
                structHash
            );
    }

    function _verify(PricePayload calldata payload, bytes calldata signature)
        internal
        view
        returns (bool)
    {
        if (block.timestamp > payload.timestamp + PAYLOAD_VALIDITY_WINDOW) return false;
        if (payload.nonce != nextNonce[payload.asset]) return false;

        bytes32 structHash =
            PriceSignatureVerifier.hashPricePayload(
                payload.asset,
                payload.price,
                payload.timestamp,
                payload.nonce
            );
        bytes32 digest = PriceSignatureVerifier.toTypedDataHash(
            PriceSignatureVerifier.domainSeparator(DOMAIN_NAME, DOMAIN_VERSION, address(this)),
            structHash
        );
        return PriceSignatureVerifier.recover(digest, signature) == oracleSigner;
    }

    function _validateAndConsume(PricePayload calldata payload, bytes calldata signature) internal {
        if (block.timestamp > payload.timestamp + PAYLOAD_VALIDITY_WINDOW) {
            revert SignedPriceOracle_ExpiredTimestamp();
        }
        if (payload.nonce != nextNonce[payload.asset]) revert SignedPriceOracle_ReplayAttack();
        nextNonce[payload.asset]++;

        bytes32 structHash =
            PriceSignatureVerifier.hashPricePayload(
                payload.asset,
                payload.price,
                payload.timestamp,
                payload.nonce
            );
        bytes32 digest = PriceSignatureVerifier.toTypedDataHash(
            PriceSignatureVerifier.domainSeparator(DOMAIN_NAME, DOMAIN_VERSION, address(this)),
            structHash
        );
        if (PriceSignatureVerifier.recover(digest, signature) != oracleSigner) {
            revert SignedPriceOracle_InvalidSignature();
        }
        usedNonces[_nonceKey(payload.asset, payload.nonce)] = true;
    }

    function _nonceKey(address asset, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(asset, nonce));
    }
}
