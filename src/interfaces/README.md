# Interfaces Directory

This directory contains all interface definitions for the IP Management Platform contracts.

## Pattern
- All events, errors, and NatSpec documentation belong in interfaces
- Implementation contracts inherit from these interfaces
- This pattern reduces bytecode size by 2-5KB per contract (critical for PolkaVM 100KB limit)

## Files
- IIPAsset.sol - IP Asset NFT interface
- ILicenseToken.sol - License Token interface
- IMarketplace.sol - Marketplace interface
- IGovernanceArbitrator.sol - Governance Arbitrator interface
- IRevenueDistributor.sol - Revenue Distributor interface

See: docs/architecture/coding-standards.md for complete pattern documentation

