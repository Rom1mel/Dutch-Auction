Status: 🚧 In Development · Type: Learning Project · Audit: Not Audited

🏆 NFT Auction Platform (Educational)
A learning project implementing a complete NFT auction system on Ethereum.

What It Does
Users can list NFTs for auction with starting price

Price decreases over time (Dutch auction style)

Bids are made with EducationToken (ERC20)

Platform collects fees on successful auctions

🏗️ Architecture
text
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  NFTsLot    │    │   Auction   │    │ Education   │
│  (ERC721)   │◄───┤   (Core)    │───►│   Token     │
└─────────────┘    └─────────────┘    └─────────────┘
       │                    │                    │
       └────────────────────┼────────────────────┘
                            ▼
                    ┌─────────────┐
                    │   Users     │
                    └─────────────┘

🛡️ Development Status
✅ Core functionality implemented

✅ Comprehensive test suite

✅ Local deployment working

🔄 Documentation in progress

❌ Upgradeable Proxy pattern not implemented

❌ Frontend interface not developed

❌ Not audited for security

❌ Not deployed to testnet

Development Tools
Hardhat: Local blockchain & testing framework

Viem: Type-safe Ethereum interactions

TypeScript: Full type safety in tests

Chai/Mocha: Assertion library & test runner

🔒 Security Disclaimer
⚠️ WARNING: This project is for educational purposes only. The code has not been professionally audited. Do not use with real Ethereum or valuable assets.