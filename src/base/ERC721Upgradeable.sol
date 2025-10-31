// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Initializable.sol";
import "./IERC721Receiver.sol";

/**
 * @dev Minimal implementation for PolkaVM deployment
 * Removes enumerable extension and URI storage to reduce bytecode size
 * Includes safe transfer receiver checks for security
 * Based on OpenZeppelin Contracts (MIT License)
 * Source: https://github.com/OpenZeppelin/openzeppelin-contracts
 */
abstract contract ERC721Upgradeable is Initializable {
    /// @dev Emitted when tokenId token is transferred from from to to
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /// @dev Emitted when owner enables approved to manage the tokenId token
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /// @dev Emitted when owner enables or disables operator to manage all of its assets
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /// @dev Token name
    string private _name;

    /// @dev Token symbol
    string private _symbol;

    /// @dev Mapping from token ID to owner address
    mapping(uint256 => address) private _owners;

    /// @dev Mapping from owner address to token count
    mapping(address => uint256) private _balances;

    /// @dev Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    /// @dev Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /**
     * @dev Initializes the contract by setting a name and symbol
     */
    function __ERC721_init(string memory name_, string memory symbol_) internal {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the token collection name
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the token collection symbol
     */
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the token URI (override in derived contracts)
     */
    function tokenURI(uint256 /* tokenId */) public view virtual returns (string memory) {
        return "";
    }

    /**
     * @dev Returns the number of tokens in owner's account
     */
    function balanceOf(address owner) public view virtual returns (uint256) {
        require(owner != address(0), "ERC721: address zero is not a valid owner");
        return _balances[owner];
    }

    /**
     * @dev Returns the owner of the tokenId
     */
    function ownerOf(uint256 tokenId) public view virtual returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: invalid token ID");
        return owner;
    }

    /**
     * @dev Approves another address to transfer the given token ID
     */
    function approve(address to, uint256 tokenId) public virtual {
        address owner = ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");
        require(
            msg.sender == owner || isApprovedForAll(owner, msg.sender),
            "ERC721: approve caller is not token owner or approved for all"
        );
        _approve(to, tokenId);
    }

    /**
     * @dev Returns the account approved for tokenId
     */
    function getApproved(uint256 tokenId) public view virtual returns (address) {
        require(_exists(tokenId), "ERC721: invalid token ID");
        return _tokenApprovals[tokenId];
    }

    /**
     * @dev Approve or remove operator as an operator for the caller
     */
    function setApprovalForAll(address operator, bool approved) public virtual {
        require(operator != msg.sender, "ERC721: approve to caller");
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /**
     * @dev Returns if the operator is allowed to manage all of the assets of owner
     */
    function isApprovedForAll(address owner, address operator) public view virtual returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /**
     * @dev Transfers tokenId from from to to
     */
    function transferFrom(address from, address to, uint256 tokenId) public virtual {
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: caller is not token owner or approved");
        _transfer(from, to, tokenId);
    }

    /**
     * @dev Safely transfers tokenId token from from to to
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev Safely transfers tokenId token from from to to with receiver check
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual {
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: caller is not token owner or approved");
        _safeTransfer(from, to, tokenId, data);
    }

    /**
     * @dev Safely transfers tokenId from from to to, checking if recipient is a contract that can receive ERC721
     */
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal virtual {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    /**
     * @dev Returns whether tokenId exists
     */
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }

    /**
     * @dev Returns whether spender is allowed to manage tokenId
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || isApprovedForAll(owner, spender) || getApproved(tokenId) == spender);
    }

    /**
     * @dev Mints tokenId and transfers it to to
     */
    function _mint(address to, uint256 tokenId) internal virtual {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: token already minted");

        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(address(0), to, tokenId);
    }

    /**
     * @dev Destroys tokenId
     */
    function _burn(uint256 tokenId) internal virtual {
        address owner = ownerOf(tokenId);

        // Clear approvals
        _approve(address(0), tokenId);

        _balances[owner] -= 1;
        delete _owners[tokenId];

        emit Transfer(owner, address(0), tokenId);
    }

    /**
     * @dev Transfers tokenId from from to to
     */
    function _transfer(address from, address to, uint256 tokenId) internal virtual {
        require(ownerOf(tokenId) == from, "ERC721: transfer from incorrect owner");
        require(to != address(0), "ERC721: transfer to the zero address");

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    /**
     * @dev Approve to to operate on tokenId
     */
    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address
     * Returns true if the call succeeded and returned the expected magic value
     */
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
        return true;
    }

    /**
     * @dev ERC-165 support
     */
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 interface ID for ERC721
            interfaceId == 0x5b5e139f;   // ERC165 interface ID for ERC721Metadata
    }
}
