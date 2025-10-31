// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../src/base/ERC721Upgradeable.sol";
import "../../src/base/IERC721Receiver.sol";

contract ERC721UpgradeableTest is Test {
    MockERC721 public nft;
    address public owner = address(1);
    address public recipient = address(2);
    address public operator = address(3);
    uint256 public constant TOKEN_ID = 1;

    function setUp() public {
        nft = new MockERC721();
        nft.initialize("Test NFT", "TNFT");
    }

    function testMetadata() public {
        assertEq(nft.name(), "Test NFT", "Name should match");
        assertEq(nft.symbol(), "TNFT", "Symbol should match");
    }

    function testMint() public {
        nft.mint(owner, TOKEN_ID);
        assertEq(nft.ownerOf(TOKEN_ID), owner, "Owner should match");
        assertEq(nft.balanceOf(owner), 1, "Balance should be 1");
    }

    function testCannotMintToZeroAddress() public {
        vm.expectRevert("ERC721: mint to the zero address");
        nft.mint(address(0), TOKEN_ID);
    }

    function testCannotMintExistingToken() public {
        nft.mint(owner, TOKEN_ID);
        vm.expectRevert("ERC721: token already minted");
        nft.mint(recipient, TOKEN_ID);
    }

    function testBurn() public {
        nft.mint(owner, TOKEN_ID);
        nft.burn(TOKEN_ID);
        vm.expectRevert("ERC721: invalid token ID");
        nft.ownerOf(TOKEN_ID);
        assertEq(nft.balanceOf(owner), 0, "Balance should be 0");
    }

    function testApprove() public {
        nft.mint(owner, TOKEN_ID);
        vm.prank(owner);
        nft.approve(recipient, TOKEN_ID);
        assertEq(nft.getApproved(TOKEN_ID), recipient, "Approved address should match");
    }

    function testCannotApproveToCurrentOwner() public {
        nft.mint(owner, TOKEN_ID);
        vm.prank(owner);
        vm.expectRevert("ERC721: approval to current owner");
        nft.approve(owner, TOKEN_ID);
    }

    function testSetApprovalForAll() public {
        vm.prank(owner);
        nft.setApprovalForAll(operator, true);
        assertTrue(nft.isApprovedForAll(owner, operator), "Operator should be approved");

        vm.prank(owner);
        nft.setApprovalForAll(operator, false);
        assertFalse(nft.isApprovedForAll(owner, operator), "Operator should not be approved");
    }

    function testCannotApproveToSelf() public {
        vm.prank(owner);
        vm.expectRevert("ERC721: approve to caller");
        nft.setApprovalForAll(owner, true);
    }

    function testTransferFrom() public {
        nft.mint(owner, TOKEN_ID);
        vm.prank(owner);
        nft.transferFrom(owner, recipient, TOKEN_ID);
        assertEq(nft.ownerOf(TOKEN_ID), recipient, "New owner should match");
        assertEq(nft.balanceOf(owner), 0, "Old owner balance should be 0");
        assertEq(nft.balanceOf(recipient), 1, "New owner balance should be 1");
    }

    function testTransferFromWithApproval() public {
        nft.mint(owner, TOKEN_ID);
        vm.prank(owner);
        nft.approve(operator, TOKEN_ID);
        vm.prank(operator);
        nft.transferFrom(owner, recipient, TOKEN_ID);
        assertEq(nft.ownerOf(TOKEN_ID), recipient, "Transfer should succeed");
    }

    function testTransferFromWithOperatorApproval() public {
        nft.mint(owner, TOKEN_ID);
        vm.prank(owner);
        nft.setApprovalForAll(operator, true);
        vm.prank(operator);
        nft.transferFrom(owner, recipient, TOKEN_ID);
        assertEq(nft.ownerOf(TOKEN_ID), recipient, "Transfer should succeed");
    }

    function testCannotTransferWithoutApproval() public {
        nft.mint(owner, TOKEN_ID);
        vm.prank(operator);
        vm.expectRevert("ERC721: caller is not token owner or approved");
        nft.transferFrom(owner, recipient, TOKEN_ID);
    }

    function testCannotTransferToZeroAddress() public {
        nft.mint(owner, TOKEN_ID);
        vm.prank(owner);
        vm.expectRevert("ERC721: transfer to the zero address");
        nft.transferFrom(owner, address(0), TOKEN_ID);
    }

    function testSafeTransferFrom() public {
        nft.mint(owner, TOKEN_ID);
        vm.prank(owner);
        nft.safeTransferFrom(owner, recipient, TOKEN_ID);
        assertEq(nft.ownerOf(TOKEN_ID), recipient, "Safe transfer should succeed");
    }

    function testSafeTransferFromWithData() public {
        nft.mint(owner, TOKEN_ID);
        vm.prank(owner);
        nft.safeTransferFrom(owner, recipient, TOKEN_ID, "test data");
        assertEq(nft.ownerOf(TOKEN_ID), recipient, "Safe transfer with data should succeed");
    }

    function testBalanceOfZeroAddress() public {
        vm.expectRevert("ERC721: address zero is not a valid owner");
        nft.balanceOf(address(0));
    }

    function testOwnerOfInvalidToken() public {
        vm.expectRevert("ERC721: invalid token ID");
        nft.ownerOf(999);
    }

    function testGetApprovedInvalidToken() public {
        vm.expectRevert("ERC721: invalid token ID");
        nft.getApproved(999);
    }

    function testSupportsInterface() public {
        assertTrue(nft.supportsInterface(0x01ffc9a7), "Should support ERC165");
        assertTrue(nft.supportsInterface(0x80ac58cd), "Should support ERC721");
        assertTrue(nft.supportsInterface(0x5b5e139f), "Should support ERC721Metadata");
        assertFalse(nft.supportsInterface(0xffffffff), "Should not support random interface");
    }

    function testSafeTransferToEOA() public {
        nft.mint(owner, TOKEN_ID);
        vm.prank(owner);
        nft.safeTransferFrom(owner, recipient, TOKEN_ID);
        assertEq(nft.ownerOf(TOKEN_ID), recipient, "Token should be transferred to recipient");
    }

    function testSafeTransferToContract() public {
        ERC721Receiver receiverContract = new ERC721Receiver();
        nft.mint(owner, TOKEN_ID);
        vm.prank(owner);
        nft.safeTransferFrom(owner, address(receiverContract), TOKEN_ID);
        assertEq(nft.ownerOf(TOKEN_ID), address(receiverContract), "Token should be transferred to receiver contract");
    }

    function testCannotSafeTransferToNonReceiverContract() public {
        NonReceiver nonReceiverContract = new NonReceiver();
        nft.mint(owner, TOKEN_ID);
        vm.prank(owner);
        vm.expectRevert("ERC721: transfer to non ERC721Receiver implementer");
        nft.safeTransferFrom(owner, address(nonReceiverContract), TOKEN_ID);
    }

    function testSafeTransferToContractWithData() public {
        ERC721Receiver receiverContract = new ERC721Receiver();
        nft.mint(owner, TOKEN_ID);
        vm.prank(owner);
        nft.safeTransferFrom(owner, address(receiverContract), TOKEN_ID, "test data");
        assertEq(nft.ownerOf(TOKEN_ID), address(receiverContract), "Token should be transferred");
    }
}

contract MockERC721 is ERC721Upgradeable {
    function initialize(string memory name_, string memory symbol_) public initializer {
        __ERC721_init(name_, symbol_);
    }

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }

    function burn(uint256 tokenId) public {
        _burn(tokenId);
    }
}

contract ERC721Receiver is IERC721Receiver {
    function onERC721Received(
        address /* operator */,
        address /* from */,
        uint256 /* tokenId */,
        bytes calldata /* data */
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract NonReceiver {
    // This contract does not implement IERC721Receiver
}
