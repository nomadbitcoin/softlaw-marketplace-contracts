// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @title MaliciousReentrantNFT
 * @notice Malicious NFT contract that attempts reentrancy during transferFrom
 * @dev Used to test reentrancy protection in IPAsset wrapping/unwrapping
 */
contract MaliciousReentrantNFT is ERC721 {
    address public targetIPAsset;
    uint256 private _tokenIdCounter;

    constructor() ERC721("Malicious", "MAL") {}

    function setTarget(address _target) external {
        targetIPAsset = _target;
    }

    function mint(address to) external returns (uint256) {
        uint256 tokenId = _tokenIdCounter++;
        _mint(to, tokenId);
        return tokenId;
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        // Attempt reentrancy attack before completing transfer
        if (targetIPAsset != address(0)) {
            try IIPAssetTarget(targetIPAsset).wrapNFT(address(this), 999, "reentrant-attack") {
                // If this succeeds, reentrancy protection failed
            } catch {
                // Expected: reentrancy protection blocks this
            }
        }
        super.transferFrom(from, to, tokenId);
    }
}

interface IIPAssetTarget {
    function wrapNFT(address nftContract, uint256 nftTokenId, string memory metadataURI)
        external
        returns (uint256);
}
