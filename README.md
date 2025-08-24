# Yield-Vault - DeFi Yield Aggregator

A sophisticated yield aggregator smart contract built on the Stacks blockchain that automatically finds and compounds the best yield opportunities across multiple DeFi protocols.

## Features

### Core Functionality

- **Multi-Strategy Yield Optimization**: Automatically allocates funds across STX staking, lending protocols, and LP farming
- **Risk-Based Vault Management**: Three risk levels (Conservative, Balanced, Aggressive) with tailored strategy allocation
- **Automated Compounding**: Harvest and reinvest earnings automatically to maximize yield
- **Share-Based Accounting**: ERC-4626-like vault standard with precise share calculations

### Advanced Features

- **Dynamic Rebalancing**: Admin-controlled strategy optimization based on market conditions
- **Emergency Controls**: Pause functionality for security and risk management
- **Fee Management**: Configurable platform and performance fees with treasury integration
- **Multi-Vault Support**: Users can participate in multiple vaults with different risk profiles

## Supported Strategies

| Strategy         | Protocol      | Risk Level    | Target APY |
| ---------------- | ------------- | ------------- | ---------- |
| STX Staking      | Native Stacks | Low (3/10)    | 12%        |
| Lending Protocol | Arkadiko      | Medium (5/10) | 8%         |
| LP Farming       | ALEX          | High (7/10)   | 15%        |

### Key Components

#### Vault System

- **Risk Levels**: Conservative (1), Balanced (2), Aggressive (3)
- **Minimum Deposits**: Configurable per vault
- **Share Calculation**: `shares = (assets * total_shares) / total_assets`

#### Fee Structure

- **Platform Fee**: 0.5% (configurable, max 10%)
- **Performance Fee**: 10% on generated yield
- **Treasury**: Automatic fee collection and management

## Installation & Deployment

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) for local development
- [Stacks CLI](https://docs.stacks.co/docs/clarity/cli/) for deployment
- STX tokens for gas fees

### Local Development

```bash
# Clone the repository
git clone https://github.com/your-org/stacks-yield.git
cd stacks-yield

# Run tests
clarinet test

# Deploy locally
clarinet deploy --devnet
```

### Mainnet Deployment

```bash
# Deploy to mainnet
stx deploy_contract stacks-yield contract.clar --network=mainnet
```

## 📖 Usage Guide

### For Users

#### Creating a Deposit

```clarity
;; Deposit 1000 STX into vault 1
(contract-call? .stacks-yield deposit u1 u1000000000)
```

#### Withdrawing Funds

```clarity
;; Withdraw 500 shares from vault 1
(contract-call? .stacks-yield withdraw u1 u500000000)
```

#### Checking Position

```clarity
;; Get user position in vault 1
(contract-call? .stacks-yield get-user-position u1 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

### For Administrators

#### Creating New Vaults

```clarity
;; Create a balanced risk vault with 10 STX minimum deposit
(contract-call? .stacks-yield create-vault "Balanced Growth Vault" u2 u10000000)
```

#### Managing Strategies

```clarity
;; Add new yield strategy
(contract-call? .stacks-yield add-strategy
  "New DeFi Strategy"
  "protocol-name"
  u1800  ;; 18% APY
  u50000000000  ;; 50k STX capacity
  u6  ;; Risk score
  'ST1STRATEGY-CONTRACT-ADDRESS)
```

## Key Functions Reference

### Public Functions

- `create-vault(name, risk-level, min-deposit)` - Create new yield vault
- `deposit(vault-id, amount)` - Deposit STX into vault
- `withdraw(vault-id, shares)` - Withdraw funds from vault
- `harvest-vault(vault-id)` - Compound vault earnings
- `rebalance-vault(vault-id, strategy-id)` - Admin rebalancing

### Read-Only Functions

- `get-vault-info(vault-id)` - Vault details and statistics
- `get-user-position(vault-id, user)` - User's position in vault
- `get-platform-stats()` - Platform-wide statistics
- `get-best-apy()` - Highest available APY across strategies

## Security Features

- **Access Control**: Role-based admin system with owner privileges
- **Emergency Pause**: Contract-wide pause functionality for security incidents
- **Input Validation**: Comprehensive parameter validation and error handling
- **Fee Limits**: Maximum fee caps to protect users from excessive charges

## Platform Statistics

Track key metrics:

- **Total Value Locked (TVL)**: Aggregate assets across all vaults
- **Active Vaults**: Number of operational yield vaults
- **Strategy Performance**: Individual strategy APYs and allocations
- **User Positions**: Portfolio tracking and performance analytics

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Workflow

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- [Stacks Documentation](https://docs.stacks.co/)
- [Clarity Language Reference](https://clarity-lang.org/)
- [Security Audits](./audits/)

## ⚠️ Disclaimer

This smart contract is provided as-is. Users should understand the risks involved in DeFi protocols including smart contract risk, market volatility, and potential loss of funds. Always DYOR (Do Your Own Research) before investing.
