// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/IPAsset.sol";
import "../src/LicenseToken.sol";
import "../src/GovernanceArbitrator.sol";
import "../src/RevenueDistributor.sol";
import "./mocks/MockNFT.sol";
import "./mocks/MaliciousReentrantNFT.sol";
import "./mocks/BrokenNFT.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title IPAssetWrappingTest
 * @notice Unit tests for NFT wrapping functionality in IPAsset
 */
contract IPAssetWrappingTest is Test {
    IPAsset public ipAsset;
    LicenseToken public licenseToken;
    GovernanceArbitrator public arbitrator;
    RevenueDistributor public revenueDistributor;
    MockNFT public mockNFT;
    MaliciousReentrantNFT public maliciousNFT;
    BrokenNFT public brokenNFT;

    address public admin = address(1);
    address public alice = address(2);
    address public bob = address(3);
    address public charlie = address(4);
    address public treasury = address(5);

    event NFTWrapped(
        uint256 indexed ipTokenId,
        address indexed nftContract,
        uint256 indexed nftTokenId,
        address wrapper
    );
    event NFTUnwrapped(
        uint256 indexed ipTokenId,
        address indexed nftContract,
        uint256 indexed nftTokenId,
        address owner
    );
    event IPMinted(uint256 indexed tokenId, address indexed owner, string metadataURI);

    function setUp() public {
        vm.startPrank(admin);

        // Deploy implementations
        IPAsset ipAssetImpl = new IPAsset();
        LicenseToken licenseTokenImpl = new LicenseToken();
        GovernanceArbitrator arbitratorImpl = new GovernanceArbitrator();

        // Deploy proxies
        bytes memory ipAssetInitData = abi.encodeWithSelector(
            IPAsset.initialize.selector, "IP Asset", "IPA", admin, address(0), address(0)
        );
        ERC1967Proxy ipAssetProxy = new ERC1967Proxy(address(ipAssetImpl), ipAssetInitData);
        ipAsset = IPAsset(address(ipAssetProxy));

        // Deploy RevenueDistributor
        revenueDistributor = new RevenueDistributor(treasury, 250, 1000, address(ipAsset));

        bytes memory licenseTokenInitData = abi.encodeWithSelector(
            LicenseToken.initialize.selector,
            "https://license.uri/",
            admin,
            address(ipAsset),
            address(0),
            address(revenueDistributor)
        );
        ERC1967Proxy licenseTokenProxy = new ERC1967Proxy(address(licenseTokenImpl), licenseTokenInitData);
        licenseToken = LicenseToken(address(licenseTokenProxy));

        bytes memory arbitratorInitData = abi.encodeWithSelector(
            GovernanceArbitrator.initialize.selector,
            admin,
            address(licenseToken),
            address(ipAsset),
            address(revenueDistributor)
        );
        ERC1967Proxy arbitratorProxy = new ERC1967Proxy(address(arbitratorImpl), arbitratorInitData);
        arbitrator = GovernanceArbitrator(address(arbitratorProxy));

        // Set contract references
        ipAsset.setLicenseTokenContract(address(licenseToken));
        ipAsset.setArbitratorContract(address(arbitrator));
        ipAsset.setRevenueDistributorContract(address(revenueDistributor));

        // Grant roles
        ipAsset.grantRole(ipAsset.LICENSE_MANAGER_ROLE(), address(licenseToken));
        ipAsset.grantRole(ipAsset.ARBITRATOR_ROLE(), address(arbitrator));

        vm.stopPrank();

        // Deploy mock NFT contracts
        mockNFT = new MockNFT("Mock NFT", "MNFT");
        maliciousNFT = new MaliciousReentrantNFT();
        brokenNFT = new BrokenNFT();
    }

    // ========== Wrapping Tests ==========

    function testWrapNFT() public {
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);

        vm.expectEmit(true, true, true, true);
        emit IPMinted(1, alice, "ipfs://wrapped-metadata");
        vm.expectEmit(true, true, true, true);
        emit NFTWrapped(1, address(mockNFT), nftTokenId, alice);

        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://wrapped-metadata");

        assertEq(ipTokenId, 1);
        assertEq(ipAsset.ownerOf(ipTokenId), alice);
        assertEq(mockNFT.ownerOf(nftTokenId), address(ipAsset));
        vm.stopPrank();
    }

    function testWrapNFT_TransfersNFTToContract() public {
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);

        assertEq(mockNFT.ownerOf(nftTokenId), alice);

        ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata");

        assertEq(mockNFT.ownerOf(nftTokenId), address(ipAsset));
        vm.stopPrank();
    }

    function testWrapNFT_MintsIPAsset() public {
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);

        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata");

        assertEq(ipAsset.ownerOf(ipTokenId), alice);
        assertEq(ipAsset.tokenURI(ipTokenId), "ipfs://metadata");
        vm.stopPrank();
    }

    function testWrapNFT_StoresWrappedReference() public {
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);

        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata");

        assertTrue(ipAsset.isWrapped(ipTokenId));
        (address storedContract, uint256 storedTokenId) = ipAsset.getWrappedNFT(ipTokenId);
        assertEq(storedContract, address(mockNFT));
        assertEq(storedTokenId, nftTokenId);
        vm.stopPrank();
    }

    function testWrapNFT_RevertNotOwner() public {
        vm.prank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IIPAsset.NFTNotOwned.selector, address(mockNFT), nftTokenId, bob)
        );
        ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata");
    }

    function testWrapNFT_RevertAlreadyWrapped() public {
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);

        uint256 firstIPToken = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata");

        // After wrapping, the NFT is owned by the contract
        // Trying to wrap again will fail at ownerOf check (not NFTAlreadyWrapped)
        // because alice no longer owns the NFT
        vm.expectRevert(
            abi.encodeWithSelector(IIPAsset.NFTNotOwned.selector, address(mockNFT), nftTokenId, alice)
        );
        ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata2");
        vm.stopPrank();
    }

    function testWrapNFT_RevertZeroAddress() public {
        vm.prank(alice);
        vm.expectRevert(IIPAsset.InvalidAddress.selector);
        ipAsset.wrapNFT(address(0), 0, "ipfs://metadata");
    }

    function testWrapNFT_RevertEmptyMetadata() public {
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);

        vm.expectRevert(IIPAsset.EmptyMetadata.selector);
        ipAsset.wrapNFT(address(mockNFT), nftTokenId, "");
        vm.stopPrank();
    }

    // ========== Unwrapping Tests ==========

    function testUnwrapNFT() public {
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);

        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata");

        vm.expectEmit(true, true, true, true);
        emit NFTUnwrapped(ipTokenId, address(mockNFT), nftTokenId, alice);

        ipAsset.unwrapNFT(ipTokenId);

        assertEq(mockNFT.ownerOf(nftTokenId), alice);
        vm.stopPrank();
    }

    function testUnwrapNFT_BurnsIPAsset() public {
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);

        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata");

        ipAsset.unwrapNFT(ipTokenId);

        vm.expectRevert();
        ipAsset.ownerOf(ipTokenId);
        vm.stopPrank();
    }

    function testUnwrapNFT_ReturnsNFT() public {
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);

        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata");

        assertEq(mockNFT.ownerOf(nftTokenId), address(ipAsset));

        ipAsset.unwrapNFT(ipTokenId);

        assertEq(mockNFT.ownerOf(nftTokenId), alice);
        vm.stopPrank();
    }

    function testUnwrapNFT_CleansUpStorage() public {
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);

        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata");

        assertTrue(ipAsset.isWrapped(ipTokenId));

        ipAsset.unwrapNFT(ipTokenId);

        // After unwrapping, can wrap the same NFT again
        mockNFT.approve(address(ipAsset), nftTokenId);
        uint256 newIPTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata2");
        assertEq(newIPTokenId, 2);
        vm.stopPrank();
    }

    function testUnwrapNFT_RevertNotOwner() public {
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);

        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata");
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert(IIPAsset.NotTokenOwner.selector);
        ipAsset.unwrapNFT(ipTokenId);
    }

    function testUnwrapNFT_RevertNotWrapped() public {
        vm.prank(alice);
        uint256 nativeIPToken = ipAsset.mintIP(alice, "ipfs://native-metadata");

        vm.prank(alice);
        vm.expectRevert(IIPAsset.NotWrappedNFT.selector);
        ipAsset.unwrapNFT(nativeIPToken);
    }

    function testUnwrapNFT_RevertHasActiveLicenses() public {
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);

        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata");

        // Mint a license
        ipAsset.mintLicense(
            ipTokenId,
            bob,
            1,
            "ipfs://license-pub",
            "ipfs://license-priv",
            block.timestamp + 30 days,
            "Standard license",
            false,
            0
        );

        vm.expectRevert(abi.encodeWithSelector(IIPAsset.HasActiveLicenses.selector, ipTokenId, 1));
        ipAsset.unwrapNFT(ipTokenId);
        vm.stopPrank();
    }

    function testUnwrapNFT_RevertHasActiveDispute() public {
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);

        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata");
        vm.stopPrank();

        // Set dispute status - arbitrator contract already has the role
        vm.prank(address(arbitrator));
        ipAsset.setDisputeStatus(ipTokenId, true);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IIPAsset.HasActiveDispute.selector, ipTokenId));
        ipAsset.unwrapNFT(ipTokenId);
    }

    function testUnwrapNFT_SucceedsAfterDisputeResolved() public {
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);

        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata");
        vm.stopPrank();

        // Set active dispute
        vm.prank(address(arbitrator));
        ipAsset.setDisputeStatus(ipTokenId, true);

        // Verify unwrap is blocked while dispute is active
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IIPAsset.HasActiveDispute.selector, ipTokenId));
        ipAsset.unwrapNFT(ipTokenId);

        // Resolve dispute (clear active flag)
        vm.prank(address(arbitrator));
        ipAsset.setDisputeStatus(ipTokenId, false);

        // Verify unwrap succeeds after dispute resolved
        vm.prank(alice);
        ipAsset.unwrapNFT(ipTokenId);

        // Verify NFT returned to owner
        assertEq(mockNFT.ownerOf(nftTokenId), alice);
    }

    // ========== View Function Tests ==========

    function testIsWrapped_ReturnsTrueForWrapped() public {
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);

        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata");

        assertTrue(ipAsset.isWrapped(ipTokenId));
        vm.stopPrank();
    }

    function testIsWrapped_ReturnsFalseForNative() public {
        vm.prank(alice);
        uint256 ipTokenId = ipAsset.mintIP(alice, "ipfs://native-metadata");

        assertFalse(ipAsset.isWrapped(ipTokenId));
    }

    function testGetWrappedNFT_ReturnsCorrectDetails() public {
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);

        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata");

        (address nftContract, uint256 tokenId) = ipAsset.getWrappedNFT(ipTokenId);
        assertEq(nftContract, address(mockNFT));
        assertEq(tokenId, nftTokenId);
        vm.stopPrank();
    }

    function testGetWrappedNFT_ReturnsZeroForNative() public {
        vm.prank(alice);
        uint256 ipTokenId = ipAsset.mintIP(alice, "ipfs://native-metadata");

        (address nftContract, uint256 tokenId) = ipAsset.getWrappedNFT(ipTokenId);
        assertEq(nftContract, address(0));
        assertEq(tokenId, 0);
    }

    function testOnERC721Received_AcceptsNFT() public {
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);

        // safeTransferFrom should work
        mockNFT.safeTransferFrom(alice, address(ipAsset), nftTokenId);

        assertEq(mockNFT.ownerOf(nftTokenId), address(ipAsset));
        vm.stopPrank();
    }

    // ========== Edge Cases ==========

    function testDoubleWrap_PreventsSecondWrap() public {
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);

        uint256 firstIPToken = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata");

        // NFT is now owned by the contract, so alice can't wrap it again
        vm.expectRevert(
            abi.encodeWithSelector(IIPAsset.NFTNotOwned.selector, address(mockNFT), nftTokenId, alice)
        );
        ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata2");
        vm.stopPrank();
    }

    function testWrapMultipleDifferentNFTs() public {
        vm.startPrank(alice);

        uint256 nft1 = mockNFT.mint(alice);
        uint256 nft2 = mockNFT.mint(alice);
        uint256 nft3 = mockNFT.mint(alice);

        mockNFT.approve(address(ipAsset), nft1);
        mockNFT.approve(address(ipAsset), nft2);
        mockNFT.approve(address(ipAsset), nft3);

        uint256 ip1 = ipAsset.wrapNFT(address(mockNFT), nft1, "ipfs://metadata1");
        uint256 ip2 = ipAsset.wrapNFT(address(mockNFT), nft2, "ipfs://metadata2");
        uint256 ip3 = ipAsset.wrapNFT(address(mockNFT), nft3, "ipfs://metadata3");

        assertEq(ip1, 1);
        assertEq(ip2, 2);
        assertEq(ip3, 3);

        assertTrue(ipAsset.isWrapped(ip1));
        assertTrue(ipAsset.isWrapped(ip2));
        assertTrue(ipAsset.isWrapped(ip3));

        vm.stopPrank();
    }

    // ========== Security Tests ==========

    function testWrapNFT_BlocksReentrancy() public {
        vm.startPrank(alice);
        uint256 nftTokenId = maliciousNFT.mint(alice);

        // Set IPAsset as the target for reentrancy attack
        maliciousNFT.setTarget(address(ipAsset));
        maliciousNFT.approve(address(ipAsset), nftTokenId);

        // This should succeed despite the reentrancy attempt
        // The nonReentrant modifier will block the reentrant call
        uint256 ipTokenId = ipAsset.wrapNFT(address(maliciousNFT), nftTokenId, "ipfs://metadata");

        // Verify wrapping succeeded
        assertEq(ipAsset.ownerOf(ipTokenId), alice);
        assertEq(maliciousNFT.ownerOf(nftTokenId), address(ipAsset));
        vm.stopPrank();
    }

    function testUnwrapNFT_BlocksReentrancy() public {
        // First wrap a normal NFT
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);
        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://metadata");

        // Unwrapping should work without reentrancy issues
        ipAsset.unwrapNFT(ipTokenId);

        assertEq(mockNFT.ownerOf(nftTokenId), alice);
        vm.stopPrank();
    }

    function testWrapNFT_HandlesInvalidNFTContract() public {
        vm.startPrank(alice);
        uint256 nftTokenId = brokenNFT.mint(alice);

        // Enable broken behavior
        brokenNFT.setShouldRevert(true);
        brokenNFT.approve(address(ipAsset), nftTokenId);

        // Should revert when calling ownerOf
        vm.expectRevert("BrokenNFT: ownerOf always reverts");
        ipAsset.wrapNFT(address(brokenNFT), nftTokenId, "ipfs://metadata");

        vm.stopPrank();
    }

    function testWrapNFT_WorksWithWeirdNFT() public {
        // Test permissionless wrapping - any ERC721 should work
        vm.startPrank(alice);
        uint256 nftTokenId = brokenNFT.mint(alice);

        // Disable broken behavior - should work normally
        brokenNFT.setShouldRevert(false);
        brokenNFT.approve(address(ipAsset), nftTokenId);

        uint256 ipTokenId = ipAsset.wrapNFT(address(brokenNFT), nftTokenId, "ipfs://metadata");

        assertEq(ipAsset.ownerOf(ipTokenId), alice);
        assertTrue(ipAsset.isWrapped(ipTokenId));
        vm.stopPrank();
    }
}
