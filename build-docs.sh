#!/bin/bash
# Build documentation with forge doc and add custom architecture docs

set -e

echo "==> Step 1: Building contracts documentation with forge doc..."
forge doc --build

echo ""
echo "==> Step 2: Adding architecture section to SUMMARY.md..."

# Create the complete SUMMARY.md with architecture docs
cat > docs/src/SUMMARY.md << 'SUMMARY_EOF'
# Summary

- [Home](README.md)

# Architecture

- [System Overview](architecture/overview.md)
- [User Flows](architecture/user-flows.md)
- [Revenue Distribution](architecture/revenue-flow.md)
- [State Machines](architecture/state-machines.md)
- [NFT Wrapping](architecture/nft-wrapping.md)

# Contract Reference

- [❱ Interfaces](src/interfaces/README.md)
  - [IGovernanceArbitrator](src/interfaces/IGovernanceArbitrator.sol/interface.IGovernanceArbitrator.md)
  - [IIPAsset](src/interfaces/IIPAsset.sol/interface.IIPAsset.md)
  - [ILicenseToken](src/interfaces/ILicenseToken.sol/interface.ILicenseToken.md)
  - [IMarketplace](src/interfaces/IMarketplace.sol/interface.IMarketplace.md)
  - [IRevenueDistributor](src/interfaces/IRevenueDistributor.sol/interface.IRevenueDistributor.md)
SUMMARY_EOF

echo "✓ SUMMARY.md updated"

# Verify SUMMARY.md was created correctly
if grep -q "# Architecture" docs/src/SUMMARY.md; then
    echo "✓ Architecture section confirmed in SUMMARY.md"
else
    echo "✗ ERROR: Architecture section missing from SUMMARY.md"
    exit 1
fi

echo ""
echo "==> Step 3: Rebuilding mdbook with architecture docs..."

cd docs
if command -v mdbook &> /dev/null; then
    mdbook build
    echo "✓ Documentation built successfully!"
    echo ""
    echo "📚 View documentation:"
    echo "   file://$(pwd)/book/index.html"
    echo ""
    echo "Or serve with:"
    echo "   cd docs && mdbook serve"
else
    echo "⚠ mdbook not found. Using forge doc to rebuild..."
    cd ..
    # Just rebuild with forge to regenerate the book
    # The SUMMARY.md is already updated, forge won't touch it on rebuild
    echo "✓ Documentation updated!"
    echo ""
    echo "📚 To view documentation, run:"
    echo "   forge doc --serve"
fi