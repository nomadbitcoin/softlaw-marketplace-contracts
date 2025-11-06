// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IIPAsset
 * @notice Interface for IP Asset NFT contract representing intellectual property ownership
 * @dev ERC-721 upgradeable contract with metadata versioning and license management
 */
interface IIPAsset {
    // ==================== EVENTS ====================

    /**
     * @notice Emitted when a new IP asset is minted
     * @param tokenId The ID of the newly minted token
     * @param owner The address that owns the new IP asset
     * @param metadataURI The URI pointing to the IP metadata
     */
    event IPMinted(uint256 indexed tokenId, address indexed owner, string metadataURI);

    /**
     * @notice Emitted when IP metadata is updated
     * @param tokenId The ID of the token being updated
     * @param oldURI The previous metadata URI
     * @param newURI The new metadata URI
     * @param timestamp The block timestamp when update occurred
     * @dev Includes old and new URIs for complete off-chain indexing without state tracking
     */
    event MetadataUpdated(uint256 indexed tokenId, string oldURI, string newURI, uint256 timestamp);

    /**
     * @notice Emitted when a license is minted for an IP asset
     * @param ipTokenId The IP asset token ID
     * @param licenseId The newly created license ID
     */
    event LicenseMinted(uint256 indexed ipTokenId, uint256 indexed licenseId);

    /**
     * @notice Emitted when revenue split is configured for an IP asset
     * @param tokenId The IP asset token ID
     * @param recipients Array of recipient addresses
     * @param shares Array of share percentages (must sum to 10000 basis points)
     */
    event RevenueSplitConfigured(uint256 indexed tokenId, address[] recipients, uint256[] shares);

    /**
     * @notice Emitted when an IP asset's dispute status changes
     * @param tokenId The IP asset token ID
     * @param hasDispute Whether the asset now has an active dispute
     */
    event DisputeStatusChanged(uint256 indexed tokenId, bool hasDispute);

    // ==================== ERRORS ====================

    /// @notice Thrown when attempting to mint to zero address
    error InvalidAddress();

    /// @notice Thrown when metadata URI is empty
    error EmptyMetadata();

    /// @notice Thrown when caller is not the token owner
    error NotTokenOwner();

    /**
     * @notice Thrown when attempting to burn a token with active licenses
     * @param tokenId The IP asset token ID
     * @param count Number of active licenses preventing the burn
     */
    error HasActiveLicenses(uint256 tokenId, uint256 count);

    /**
     * @notice Thrown when attempting to burn a token with an active dispute
     * @param tokenId The IP asset token ID
     */
    error HasActiveDispute(uint256 tokenId);

    /**
     * @notice Thrown when attempting to decrement license count below zero
     * @param tokenId The IP asset token ID
     * @param current Current license count
     * @param attempted Amount attempting to decrement
     */
    error LicenseCountUnderflow(uint256 tokenId, uint256 current, uint256 attempted);

    // ==================== FUNCTIONS ====================

    /**
     * @notice Initializes the IPAsset contract (proxy pattern)
     * @dev Sets up ERC721, AccessControl, Pausable, and UUPS upgradeable patterns
     * @param name The name for the ERC721 token
     * @param symbol The symbol for the ERC721 token
     * @param admin Address to receive all initial admin roles (DEFAULT_ADMIN, PAUSER, UPGRADER)
     * @param licenseToken Address of the LicenseToken contract
     * @param arbitrator Address of the GovernanceArbitrator contract
     */
    function initialize(
        string memory name,
        string memory symbol,
        address admin,
        address licenseToken,
        address arbitrator
    ) external;

    /**
     * @notice Mints a new IP asset NFT
     * @dev Creates a token with auto-incrementing ID and stores initial metadata
     * @param to Address to receive the newly minted IP asset
     * @param metadataURI IPFS or HTTP URI pointing to IP metadata
     * @return tokenId The ID of the newly minted token
     */
    function mintIP(address to, string memory metadataURI) external returns (uint256 tokenId);

    /**
     * @notice Creates a new license for an IP asset
     * @dev Only the IP asset owner can mint licenses. Delegates to LicenseToken contract.
     * @param ipTokenId The IP asset to create a license for
     * @param licensee Address to receive the license
     * @param amount Number of license tokens to mint (for semi-fungible licenses)
     * @param publicMetadataURI Publicly visible license metadata URI
     * @param privateMetadataURI Private license terms URI (access controlled)
     * @param expiryTime Unix timestamp when license expires
     * @param royaltyBasisPoints Royalty rate in basis points (e.g., 1000 = 10%)
     * @param terms Human-readable license terms
     * @param isExclusive Whether this is an exclusive license
     * @return licenseId The ID of the newly created license
     */
    function mintLicense(
        uint256 ipTokenId,
        address licensee,
        uint256 amount,
        string memory publicMetadataURI,
        string memory privateMetadataURI,
        uint256 expiryTime,
        uint256 royaltyBasisPoints,
        string memory terms,
        bool isExclusive
    ) external returns (uint256 licenseId);

    /**
     * @notice Updates the metadata URI for an IP asset
     * @dev Only the token owner can update. Creates a new version in history.
     * @param tokenId The IP asset token ID
     * @param newURI The new metadata URI
     */
    function updateMetadata(uint256 tokenId, string memory newURI) external;

    /**
     * @notice Configures revenue split for an IP asset
     * @dev Only the token owner can configure. Delegates to RevenueDistributor.
     * @param tokenId The IP asset token ID
     * @param recipients Array of addresses to receive revenue shares
     * @param shares Array of share amounts in basis points (must sum to 10000)
     */
    function configureRevenueSplit(
        uint256 tokenId,
        address[] memory recipients,
        uint256[] memory shares
    ) external;

    /**
     * @notice Burns an IP asset NFT
     * @dev Only owner can burn. Blocked if active licenses exist or dispute is active.
     * @param tokenId The IP asset token ID to burn
     */
    function burn(uint256 tokenId) external;

    /**
     * @notice Sets the dispute status for an IP asset
     * @dev Only callable by ARBITRATOR_ROLE (GovernanceArbitrator contract)
     * @param tokenId The IP asset token ID
     * @param hasDispute Whether there is an active dispute
     */
    function setDisputeStatus(uint256 tokenId, bool hasDispute) external;

    /**
     * @notice Updates the LicenseToken contract address
     * @dev Only callable by admin
     * @param licenseToken New LicenseToken contract address
     */
    function setLicenseTokenContract(address licenseToken) external;

    /**
     * @notice Updates the GovernanceArbitrator contract address
     * @dev Only callable by admin
     * @param arbitrator New GovernanceArbitrator contract address
     */
    function setArbitratorContract(address arbitrator) external;

    /**
     * @notice Updates the active license count for an IP asset
     * @dev Only callable by LICENSE_MANAGER_ROLE (LicenseToken contract)
     * @param tokenId The IP asset token ID
     * @param delta Change in license count (positive or negative)
     */
    function updateActiveLicenseCount(uint256 tokenId, int256 delta) external;

    /**
     * @notice Checks if an IP asset has an active dispute
     * @param tokenId The IP asset token ID
     * @return hasDispute Whether there is an active dispute
     */
    function hasActiveDispute(uint256 tokenId) external view returns (bool hasDispute);

    /**
     * @notice Pauses all state-changing operations
     * @dev Only callable by PAUSER_ROLE
     */
    function pause() external;

    /**
     * @notice Unpauses all state-changing operations
     * @dev Only callable by PAUSER_ROLE
     */
    function unpause() external;
}
