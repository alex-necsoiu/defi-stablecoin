<h1 align="left">🪙 DeFi Stablecoin Protocol</h1>
<p align="left">
  <b>Decentralized, overcollateralized stablecoin system built with Solidity and Foundry</b>
</p>
<p align="left">
  <img alt="Solidity version" src="https://img.shields.io/badge/Solidity-%5E0.8.30-blue?logo=solidity">
  <img alt="Foundry" src="https://img.shields.io/badge/Built%20With-Foundry-orange?logo=foundry">
  <img alt="License" src="https://img.shields.io/badge/License-MIT-green">
  <img alt="Tests" src="https://img.shields.io/badge/Tests-100%25%20Coverage-brightgreen">
</p>

---

## 🚀 Overview

This project implements a decentralized stablecoin protocol inspired by MakerDAO, using exogenous collateral (ETH & BTC) and Chainlink price feeds to maintain a $1.00 peg. The protocol is designed for security, transparency, and extensibility, leveraging the latest OpenZeppelin Contracts v5.x and Foundry tooling.

---

## 🏗️ Features

- **💵 Stablecoin Minting:** Users can mint stablecoins by depositing ETH or BTC as collateral.
- **🔗 Chainlink Oracles:** Reliable price feeds for accurate collateral valuation.
- **🛡️ Overcollateralization:** Ensures system solvency and user safety.
- **⚡ Fast Development:** Built with [Foundry](https://book.getfoundry.sh/) for blazing fast testing and deployment.
- **🧩 Modular Architecture:** Clean separation of concerns for maintainability and extensibility.
- **🔒 Security:** Uses OpenZeppelin’s latest best practices and libraries.

---

## 📁 Project Structure

```
defi-stablecoin/
├── src/                # Core smart contracts
│   ├── DecentralizedStableCoin.sol
│   └── DSCEngine.sol
├── script/             # Deployment and helper scripts
├── test/               # Unit and integration tests
│   └── unit/
├── lib/                # External dependencies (OpenZeppelin, Chainlink, etc.)
├── out/                # Build artifacts (gitignored)
├── foundry.toml        # Foundry configuration
└── .gitignore
```

---

## 🧩 Contract Layout & Design Principles

A well-structured smart contract is crucial for readability, maintainability, and security.  
This project follows a clear and modular layout inspired by industry best practices and the [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html).

---

### 📑 Contract Section Order

| #   | Section                      | Description                                                                                 |
|-----|------------------------------|---------------------------------------------------------------------------------------------|
| 1   | **Version Pragma**           | Specifies the Solidity compiler version for clarity and reproducibility.                    |
| 2   | **Imports**                  | External dependencies, libraries, and interfaces.                                           |
| 3   | **Interfaces/Libraries**     | Custom interfaces or libraries used by the contract.                                        |
| 4   | **Errors**                   | Custom error definitions for efficient and descriptive revert reasons.                      |
| 5   | **Type Declarations**        | Structs, enums, and type aliases for strong typing and clarity.                             |
| 6   | **State Variables**          | All storage variables, grouped by visibility and purpose.                                   |
| 7   | **Events**                   | Emitted logs for off-chain tracking and analytics.                                          |
| 8   | **Modifiers**                | Custom function modifiers for access control and logic reuse.                               |
| 9   | **Functions**                | All contract logic, organized by visibility and purpose.                                    |

---

### 🛠️ Function Layout Order

| #   | Function Type         | Purpose                                                                                   |
|-----|-----------------------|-------------------------------------------------------------------------------------------|
| 1   | **constructor**       | Initializes contract state and dependencies.                                               |
| 2   | **receive**           | Handles plain Ether transfers (if present).                                                |
| 3   | **fallback**          | Handles calls to non-existent functions (if present).                                      |
| 4   | **external**          | Functions callable from outside the contract.                                              |
| 5   | **public**            | Functions callable from within and outside the contract.                                   |
| 6   | **internal**          | Functions callable only within the contract or derived contracts.                          |
| 7   | **private**           | Functions callable only within the contract itself.                                        |
| 8   | **view & pure**       | Read-only and computation-only functions, typically placed at the end.                     |

---

> **Why this layout?**  
> 🧑‍💻 **Readability:** Developers can quickly find and understand each part of the contract.  
> 🛡️ **Security:** Grouping errors, modifiers, and state variables makes it easier to audit.  
> 🧩 **Maintainability:** Logical separation of concerns simplifies future upgrades and debugging.

---

## ⚙️ Usage

### 🛠️ Build

```sh
forge build
```

### 🧪 Test

```sh
forge test
```

### 🧹 Format

```sh
forge fmt
```

### ⛽ Gas Snapshots

```sh
forge snapshot
```

### 🏦 Local Node

```sh
anvil
```

### 🚀 Deploy

```sh
forge script script/DeployDSC.s.sol:DeployDSC --rpc-url <your_rpc_url> --private-key <your_private_key>
```

---

## 📚 Documentation

- [Foundry Book](https://book.getfoundry.sh/)
- [OpenZeppelin Contracts v5.x](https://docs.openzeppelin.com/contracts/5.x/)
- [Chainlink Docs](https://docs.chain.link/)

---

## 🧑‍💻 Development Notes

- **Dependencies:**  
  - OpenZeppelin Contracts v5.x  
  - Chainlink Brownie Contracts  
- **Remappings:**  
  Ensure your `foundry.toml` includes:
  ```toml
  remappings = [
      'chainlink/=lib/chainlink-brownie-contracts/contracts/',
      'openzeppelin-contracts/=lib/openzeppelin-contracts/contracts/'
  ]
  ```
- **Security:**  
  - All external calls use [ReentrancyGuard](https://docs.openzeppelin.com/contracts/5.x/api/utils#ReentrancyGuard) and [SafeERC20](https://docs.openzeppelin.com/contracts/5.x/api/token/erc20#SafeERC20).
  - Chainlink oracles are used for all price feeds.

---

## 🧪 Testing

- All core logic is covered by unit tests in `/test/unit`.
- Run a specific test:
  ```sh
  forge test -m <TestFunctionName>
  ```

---

## 🙏 Acknowledgements

- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts)
- [Chainlink](https://github.com/smartcontractkit/chainlink)
- [Foundry](https://github.com/foundry-rs/foundry)

---

## 📝 License

This project is licensed under the MIT License.

---
