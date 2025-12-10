// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IRevenueDistributor.sol";
import "./interfaces/IIPAsset.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract RevenueDistributor is IRevenueDistributor, ReentrancyGuard, AccessControl, IERC2981 {
    // State variables
    address public platformTreasury;
    uint256 public platformFeeBasisPoints;
    uint256 public defaultRoyaltyBasisPoints;
    address public ipAssetContract;

    mapping(uint256 => Split) private _ipSplits;
    mapping(address => uint256) private _balances;
    mapping(uint256 => uint256) public assetRoyaltyBasisPoints;

    /// @notice Role for configuring revenue splits
    bytes32 public constant CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");

    /// @notice Basis points denominator (100% = 10000 bp)
    uint256 public constant BASIS_POINTS = 10000;

    constructor(
        address _treasury,
        uint256 _platformFeeBasisPoints,
        uint256 _defaultRoyaltyBasisPoints,
        address _ipAssetContract
    ) {
        if (_treasury == address(0)) revert InvalidTreasuryAddress();
        if (_platformFeeBasisPoints > 10000) revert InvalidPlatformFee();
        if (_defaultRoyaltyBasisPoints > 10000) revert InvalidRoyalty();
        if (_ipAssetContract == address(0)) revert InvalidIPAssetAddress();

        platformTreasury = _treasury;
        platformFeeBasisPoints = _platformFeeBasisPoints;
        defaultRoyaltyBasisPoints = _defaultRoyaltyBasisPoints;
        ipAssetContract = _ipAssetContract;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CONFIGURATOR_ROLE, ipAssetContract);
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

    function distributePayment(
        uint256 ipAssetId,
        uint256 amount,
        address seller
    ) external payable nonReentrant {
        if (msg.value != amount) revert IncorrectPaymentAmount();

        // Get IP asset owner using ownerOf from ERC721
        address owner = IERC721(ipAssetContract).ownerOf(ipAssetId);
        if (owner == address(0)) revert InvalidIPAsset();

        // 1. Platform fee deduction
        uint256 platformFee = (amount * platformFeeBasisPoints) / BASIS_POINTS;
        if (platformFee > 0) {
            _balances[platformTreasury] += platformFee;
        }
        uint256 remaining = amount - platformFee;

        Split storage split = _ipSplits[ipAssetId];

        // If no split configured, fall back to owner (backwards compatibility)
        if (split.recipients.length == 0) {
            _balances[owner] += remaining;
            emit PaymentDistributed(ipAssetId, amount, seller, true); // Treat as primary sale
            return;
        }

        // 2. Auto-detect sale type
        bool isPrimarySale = _isRecipientInSplit(seller, split.recipients);

        if (isPrimarySale) {
            // PRIMARY SALE: Full amount to split recipients
            for (uint256 i = 0; i < split.recipients.length; i++) {
                uint256 share = (remaining * split.shares[i]) / BASIS_POINTS;
                _balances[split.recipients[i]] += share;
            }
        } else {
            // SECONDARY SALE: Royalty to split, remainder to seller
            uint256 royaltyRate = getAssetRoyalty(ipAssetId);
            uint256 royaltyAmount = (remaining * royaltyRate) / BASIS_POINTS;

            // Distribute royalty to split recipients
            for (uint256 i = 0; i < split.recipients.length; i++) {
                uint256 royaltyShare = (royaltyAmount * split.shares[i]) / BASIS_POINTS;
                _balances[split.recipients[i]] += royaltyShare;
            }

            // Seller gets remainder
            _balances[seller] += (remaining - royaltyAmount);
        }

        emit PaymentDistributed(ipAssetId, amount, seller, isPrimarySale);
    }

    function withdraw() external nonReentrant {
        uint256 balance = _balances[msg.sender];
        if (balance == 0) revert NoBalanceToWithdraw();

        delete _balances[msg.sender];

        (bool success,) = msg.sender.call{value: balance}("");
        if (!success) revert TransferFailed();

        emit Withdrawal(msg.sender, balance);
    }

    function getBalance(address recipient) external view returns (uint256 balance) {
        return _balances[recipient];
    }

    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view override returns (
        address receiver,
        uint256 royaltyAmount
    ) {
        uint256 royaltyRate = getAssetRoyalty(tokenId);
        royaltyAmount = (salePrice * royaltyRate) / BASIS_POINTS;
        receiver = address(this);
    }

    function setDefaultRoyalty(uint256 basisPoints) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (basisPoints > 10000) revert InvalidBasisPoints();
        defaultRoyaltyBasisPoints = basisPoints;
        emit RoyaltyUpdated(basisPoints);
    }

    function setAssetRoyalty(uint256 ipAssetId, uint256 basisPoints)
        external
        onlyRole(CONFIGURATOR_ROLE)
    {
        if (basisPoints > BASIS_POINTS) revert InvalidRoyaltyRate();
        assetRoyaltyBasisPoints[ipAssetId] = basisPoints;
        emit AssetRoyaltyUpdated(ipAssetId, basisPoints);
    }

    function getAssetRoyalty(uint256 ipAssetId) public view returns (uint256) {
        uint256 customRate = assetRoyaltyBasisPoints[ipAssetId];
        return customRate > 0 ? customRate : defaultRoyaltyBasisPoints;
    }

    function grantConfiguratorRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) revert InvalidRecipient();
        _grantRole(CONFIGURATOR_ROLE, account);
    }

    function ipSplits(uint256 ipAssetId) external view returns (
        address[] memory recipients,
        uint256[] memory shares
    ) {
        return (_ipSplits[ipAssetId].recipients, _ipSplits[ipAssetId].shares);
    }

    function isSplitConfigured(uint256 ipAssetId) external view returns (bool configured) {
        return _ipSplits[ipAssetId].recipients.length > 0;
    }

    function _isRecipientInSplit(address addr, address[] memory recipients)
        internal
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == addr) return true;
        }
        return false;
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }
}
