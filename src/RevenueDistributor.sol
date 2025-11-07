// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IRevenueDistributor.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

contract RevenueDistributor is IRevenueDistributor, ReentrancyGuard, AccessControl, IERC2981 {
    // State variables
    address public platformTreasury;
    uint256 public platformFeeBasisPoints;
    uint256 public defaultRoyaltyBasisPoints;

    mapping(uint256 => Split) private _ipSplits;

    /// @notice Role for configuring revenue splits
    bytes32 public constant CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");

    /// @notice Basis points denominator (100% = 10000 bp)
    uint256 public constant BASIS_POINTS = 10000;

    constructor(
        address _treasury,
        uint256 _platformFeeBasisPoints,
        uint256 _defaultRoyaltyBasisPoints
    ) {
        require(_treasury != address(0), "Invalid treasury address");
        require(_platformFeeBasisPoints <= 10000, "Invalid platform fee");
        require(_defaultRoyaltyBasisPoints <= 10000, "Invalid royalty");

        platformTreasury = _treasury;
        platformFeeBasisPoints = _platformFeeBasisPoints;
        defaultRoyaltyBasisPoints = _defaultRoyaltyBasisPoints;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function configureSplit(
        uint256 ipAssetId,
        address[] memory recipients,
        uint256[] memory shares
    ) external onlyRole(CONFIGURATOR_ROLE) {
        if (recipients.length != shares.length) revert ArrayLengthMismatch();
        if (recipients.length == 0) revert NoRecipientsProvided();

        uint256 totalShares = 0;
        for (uint256 i = 0; i < shares.length; i++) {
            if (recipients[i] == address(0)) revert InvalidRecipient();
            totalShares += shares[i];
        }
        if (totalShares != 10000) revert InvalidSharesSum();

        _ipSplits[ipAssetId] = Split({
            recipients: recipients,
            shares: shares
        });
        emit SplitConfigured(ipAssetId, recipients, shares);
    }

    function distributePayment(uint256 ipAssetId, uint256 amount) external payable {
        uint256 platformFee = (amount * platformFeeBasisPoints) / BASIS_POINTS;
        emit PaymentDistributed(ipAssetId, amount, platformFee);
    }

    function withdraw() external {
        emit Withdrawal(msg.sender, 0, 0, 0);
    }

    function getBalanceWithInterest(address recipient) external view returns (
        uint256 principal,
        uint256 interest,
        uint256 total
    ) {
        return (0, 0, 0);
    }

    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view override returns (
        address receiver,
        uint256 royaltyAmount
    ) {
        return (address(this), (salePrice * defaultRoyaltyBasisPoints) / BASIS_POINTS);
    }

    function setDefaultRoyalty(uint256 basisPoints) external {
        defaultRoyaltyBasisPoints = basisPoints;
    }

    function grantConfiguratorRole(address ipAssetContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (ipAssetContract == address(0)) revert InvalidRecipient();
        _grantRole(CONFIGURATOR_ROLE, ipAssetContract);
    }

    function ipSplits(uint256 ipAssetId) external view returns (
        address[] memory recipients,
        uint256[] memory shares
    ) {
        return (_ipSplits[ipAssetId].recipients, _ipSplits[ipAssetId].shares);
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    receive() external payable {}
}
