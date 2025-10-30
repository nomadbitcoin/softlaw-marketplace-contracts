// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IRevenueDistributor.sol";

contract RevenueDistributor is IRevenueDistributor {
    // State variables
    address public treasury;
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
        treasury = _treasury;
        platformFeeBasisPoints = _platformFeeBasisPoints;
        defaultRoyaltyBasisPoints = _defaultRoyaltyBasisPoints;
    }

    function configureSplit(
        uint256 ipAssetId,
        address[] memory recipients,
        uint256[] memory shares
    ) external {
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

    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (
        address receiver,
        uint256 royaltyAmount
    ) {
        return (address(this), (salePrice * defaultRoyaltyBasisPoints) / BASIS_POINTS);
    }

    function setDefaultRoyalty(uint256 basisPoints) external {
        defaultRoyaltyBasisPoints = basisPoints;
    }

    function ipSplits(uint256 ipAssetId) external view returns (
        address[] memory recipients,
        uint256[] memory shares
    ) {
        return (_ipSplits[ipAssetId].recipients, _ipSplits[ipAssetId].shares);
    }

    function grantRole(bytes32 role, address account) external {}

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x2a55205a; // EIP-2981
    }

    receive() external payable {}
}
