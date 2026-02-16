// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PriceRouter} from "../src/PriceRouter.sol";
import {SignedPriceOracle} from "../src/SignedPriceOracle.sol";
import {MockChainlinkFeed} from "./mocks/MockChainlinkFeed.sol";
import {MockCollateral} from "./mocks/MockCollateral.sol";
import {IPriceRouter} from "../src/interfaces/IPriceRouter.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {PriceSignatureVerifier} from "../src/libraries/PriceSignatureVerifier.sol";

contract PriceRouterTest is Test {
    PriceRouter public router;
    SignedPriceOracle public signedOracle;
    MockChainlinkFeed public chainlinkFeed;
    MockCollateral public collateral;

    address public owner;
    uint256 public oracleKey = 0xA11CE;

    function setUp() public {
        owner = makeAddr("owner");
        router = new PriceRouter();
        router.transferOwnership(owner);

        address signer = vm.addr(oracleKey);
        signedOracle = new SignedPriceOracle(signer);

        // 1e8 = $1 (Chainlink 8 decimals)
        chainlinkFeed = new MockChainlinkFeed(1e8);

        collateral = new MockCollateral();
        collateral.mint(address(this), 1000e18);
    }

    function _signPricePayload(IPriceOracle.PricePayload memory payload)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = signedOracle.getPricePayloadDigest(payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oracleKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // -------------------------------------------------------------------------
    // Chainlink read
    // -------------------------------------------------------------------------

    function test_ChainlinkFeed_ReadsPrice() public {
        vm.startPrank(owner);
        router.setChainlinkFeed(address(collateral), address(chainlinkFeed));
        router.setSource(address(collateral), IPriceRouter.Source.CHAINLINK);
        vm.stopPrank();

        (uint256 price, uint256 updatedAt, bool isStale) =
            router.getPriceUSD8(address(collateral));

        assertEq(price, 1e8);
        assertEq(updatedAt, block.timestamp);
        assertFalse(isStale);
    }

    function test_ChainlinkFeed_StalenessFlag() public {
        vm.startPrank(owner);
        router.setChainlinkFeed(address(collateral), address(chainlinkFeed));
        router.setSource(address(collateral), IPriceRouter.Source.CHAINLINK);
        router.setStalePeriod(address(collateral), 60);
        vm.stopPrank();

        vm.warp(block.timestamp + 61);

        (, uint256 updatedAt, bool isStale) = router.getPriceUSD8(address(collateral));
        assertTrue(isStale);
        assertLt(updatedAt, block.timestamp);
    }

    function test_ChainlinkFeed_NotStaleWithinPeriod() public {
        vm.startPrank(owner);
        router.setChainlinkFeed(address(collateral), address(chainlinkFeed));
        router.setSource(address(collateral), IPriceRouter.Source.CHAINLINK);
        router.setStalePeriod(address(collateral), 3600);
        vm.stopPrank();

        vm.warp(block.timestamp + 1800);

        (, , bool isStale) = router.getPriceUSD8(address(collateral));
        assertFalse(isStale);
    }

    function test_ChainlinkFeed_PriceUpdate() public {
        vm.startPrank(owner);
        router.setChainlinkFeed(address(collateral), address(chainlinkFeed));
        router.setSource(address(collateral), IPriceRouter.Source.CHAINLINK);
        vm.stopPrank();

        chainlinkFeed.setPrice(2000e8);

        (uint256 price,,) = router.getPriceUSD8(address(collateral));
        assertEq(price, 2000e8);
    }

    // -------------------------------------------------------------------------
    // Signed oracle read
    // -------------------------------------------------------------------------

    function test_SignedOracle_ReadAfterVerify() public {
        IPriceOracle.PricePayload memory payload = IPriceOracle.PricePayload({
            asset: address(collateral),
            price: 1e8,
            timestamp: block.timestamp,
            nonce: signedOracle.nextNonce(address(collateral))
        });
        bytes memory sig = _signPricePayload(payload);
        signedOracle.verifyPricePayload(payload, sig);

        vm.startPrank(owner);
        router.setSignedOracle(address(collateral), address(signedOracle));
        router.setSource(address(collateral), IPriceRouter.Source.SIGNED);
        vm.stopPrank();

        (uint256 price, uint256 updatedAt, bool isStale) =
            router.getPriceUSD8(address(collateral));

        assertEq(price, 1e8);
        assertEq(updatedAt, block.timestamp);
        assertFalse(isStale);
    }

    function test_SignedOracle_StalenessFlag() public {
        IPriceOracle.PricePayload memory payload = IPriceOracle.PricePayload({
            asset: address(collateral),
            price: 1e8,
            timestamp: block.timestamp,
            nonce: signedOracle.nextNonce(address(collateral))
        });
        signedOracle.verifyPricePayload(payload, _signPricePayload(payload));

        vm.startPrank(owner);
        router.setSignedOracle(address(collateral), address(signedOracle));
        router.setSource(address(collateral), IPriceRouter.Source.SIGNED);
        router.setStalePeriod(address(collateral), 60);
        vm.stopPrank();

        vm.warp(block.timestamp + 61);

        (, , bool isStale) = router.getPriceUSD8(address(collateral));
        assertTrue(isStale);
    }

    // -------------------------------------------------------------------------
    // updateSignedPriceAndGet (Option B)
    // -------------------------------------------------------------------------

    function test_UpdateSignedPriceAndGet_ReturnsUSD8() public {
        vm.startPrank(owner);
        router.setSignedOracle(address(collateral), address(signedOracle));
        router.setSource(address(collateral), IPriceRouter.Source.SIGNED);
        vm.stopPrank();

        uint256 expectedPriceUSD8 = 2500e8;
        IPriceOracle.PricePayload memory payload = IPriceOracle.PricePayload({
            asset: address(collateral),
            price: expectedPriceUSD8,
            timestamp: block.timestamp,
            nonce: signedOracle.nextNonce(address(collateral))
        });
        bytes memory sig = _signPricePayload(payload);

        uint256 price = router.updateSignedPriceAndGet(address(collateral), payload, sig);

        assertEq(price, expectedPriceUSD8, "updateSignedPriceAndGet returns USD8");

        (uint256 readPrice,,) = router.getPriceUSD8(address(collateral));
        assertEq(readPrice, expectedPriceUSD8);
    }

    function test_UpdateSignedPriceAndGet_WrongAsset_Reverts() public {
        address otherAsset = makeAddr("other");
        vm.startPrank(owner);
        router.setSignedOracle(address(collateral), address(signedOracle));
        router.setSource(address(collateral), IPriceRouter.Source.SIGNED);
        vm.stopPrank();

        IPriceOracle.PricePayload memory payload = IPriceOracle.PricePayload({
            asset: address(collateral),
            price: 1e8,
            timestamp: block.timestamp,
            nonce: signedOracle.nextNonce(address(collateral))
        });
        bytes memory sig = _signPricePayload(payload);

        vm.expectRevert(PriceRouter.PriceRouter_InvalidSource.selector);
        router.updateSignedPriceAndGet(otherAsset, payload, sig);
    }

    function test_UpdateSignedPriceAndGet_ChainlinkSource_Reverts() public {
        vm.startPrank(owner);
        router.setChainlinkFeed(address(collateral), address(chainlinkFeed));
        router.setSource(address(collateral), IPriceRouter.Source.CHAINLINK);
        vm.stopPrank();

        IPriceOracle.PricePayload memory payload = IPriceOracle.PricePayload({
            asset: address(collateral),
            price: 1e8,
            timestamp: block.timestamp,
            nonce: signedOracle.nextNonce(address(collateral))
        });
        bytes memory sig = _signPricePayload(payload);

        vm.expectRevert(PriceRouter.PriceRouter_InvalidSource.selector);
        router.updateSignedPriceAndGet(address(collateral), payload, sig);
    }

    // -------------------------------------------------------------------------
    // Source switching
    // -------------------------------------------------------------------------

    function test_SourceSwitching_ChainlinkToSigned() public {
        vm.startPrank(owner);
        router.setChainlinkFeed(address(collateral), address(chainlinkFeed));
        router.setSignedOracle(address(collateral), address(signedOracle));
        router.setSource(address(collateral), IPriceRouter.Source.CHAINLINK);
        vm.stopPrank();

        (uint256 price1,,) = router.getPriceUSD8(address(collateral));
        assertEq(price1, 1e8);

        vm.prank(owner);
        router.setSource(address(collateral), IPriceRouter.Source.SIGNED);

        // No price from signed yet - need to verify first
        (uint256 price2,,) = router.getPriceUSD8(address(collateral));
        assertEq(price2, 0);

        IPriceOracle.PricePayload memory payload = IPriceOracle.PricePayload({
            asset: address(collateral),
            price: 999e8,
            timestamp: block.timestamp,
            nonce: signedOracle.nextNonce(address(collateral))
        });
        signedOracle.verifyPricePayload(payload, _signPricePayload(payload));

        (uint256 price3,,) = router.getPriceUSD8(address(collateral));
        assertEq(price3, 999e8);
    }

    function test_NoSource_ReturnsZeroAndStale() public view {
        (uint256 price, uint256 updatedAt, bool isStale) =
            router.getPriceUSD8(address(collateral));

        assertEq(price, 0);
        assertEq(updatedAt, 0);
        assertTrue(isStale);
    }

    function test_ChainlinkFeed_ZeroAnswer_Reverts() public {
        chainlinkFeed.setPrice(0);

        vm.startPrank(owner);
        router.setChainlinkFeed(address(collateral), address(chainlinkFeed));
        router.setSource(address(collateral), IPriceRouter.Source.CHAINLINK);
        vm.stopPrank();

        vm.expectRevert(PriceRouter.PriceRouter_InvalidAnswer.selector);
        router.getPriceUSD8(address(collateral));
    }

    function test_ChainlinkFeed_DecimalsNormalization() public {
        chainlinkFeed.setDecimals(18);
        chainlinkFeed.setPrice(1e18); // $1 in 18 decimals

        vm.startPrank(owner);
        router.setChainlinkFeed(address(collateral), address(chainlinkFeed));
        router.setSource(address(collateral), IPriceRouter.Source.CHAINLINK);
        vm.stopPrank();

        (uint256 price,,) = router.getPriceUSD8(address(collateral));
        assertEq(price, 1e8); // Normalized to 8 decimals
    }
}
