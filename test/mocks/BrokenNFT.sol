// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @title BrokenNFT
 * @notice NFT contract with configurable broken behavior for testing error handling
 * @dev Can be configured to revert on ownerOf to test graceful failure handling
 */
contract BrokenNFT is ERC721 {
    uint256 private _tokenIdCounter;
    bool public shouldRevert = false;

    constructor() ERC721("Broken", "BRK") {}

    function mint(address to) external returns (uint256) {
        uint256 tokenId = _tokenIdCounter++;
        _mint(to, tokenId);
        return tokenId;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        if (shouldRevert) {
            revert("BrokenNFT: ownerOf always reverts");
        }
        return super.ownerOf(tokenId);
    }
}
