
import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const alice = accounts.get("wallet_1")!;
const bob = accounts.get("wallet_2")!;

const CONTRACT_NAME = "yield_vault";

describe("Yield Vault - Initialization Tests", () => {
  it("should initialize contract with correct default values", () => {
    const { result } = simnet.callReadOnlyFn(
      CONTRACT_NAME,
      "get-platform-stats",
      [],
      deployer
    );
    
    expect(result).toBeOk(
      Cl.tuple({
        "total-value-locked": Cl.uint(0),
        "total-vaults": Cl.uint(0),
        "total-strategies": Cl.uint(3),
        "platform-fee-rate": Cl.uint(50),
        "emergency-pause": Cl.bool(false),
      })
    );
  });

  it("should have pre-initialized strategies", () => {
    // Check strategy 1 - STX Staking
    const { result: strategy1 } = simnet.callReadOnlyFn(
      CONTRACT_NAME,
      "get-strategy-info",
      [Cl.uint(1)],
      deployer
    );
    
    expect(strategy1).toBeSome(
      Cl.tuple({
        "name": Cl.stringAscii("STX-Staking-Strategy"),
        "protocol": Cl.stringAscii("stx-vault"),
        "apy": Cl.uint(1200),
        "tvl-capacity": Cl.uint(100000000000),
        "current-tvl": Cl.uint(0),
        "risk-score": Cl.uint(3),
        "is-active": Cl.bool(true),
        "contract-address": Cl.standardPrincipal(deployer),
        "last-updated": Cl.uint(simnet.blockHeight),
      })
    );

    // Check strategy 2 - Lending Protocol  
    const { result: strategy2 } = simnet.callReadOnlyFn(
      CONTRACT_NAME,
      "get-strategy-info",
      [Cl.uint(2)],
      deployer
    );
    
    expect(strategy2).toBeSome(
      Cl.tuple({
        "name": Cl.stringAscii("Lending-Protocol-Strategy"),
        "protocol": Cl.stringAscii("arkadiko"),
        "apy": Cl.uint(800),
        "tvl-capacity": Cl.uint(50000000000),
        "current-tvl": Cl.uint(0),
        "risk-score": Cl.uint(5),
        "is-active": Cl.bool(true),
        "contract-address": Cl.standardPrincipal(deployer),
        "last-updated": Cl.uint(simnet.blockHeight),
      })
    );
  });

  it("should correctly identify admin users", () => {
    const { result: deployerAdmin } = simnet.callReadOnlyFn(
      CONTRACT_NAME,
      "is-user-admin",
      [Cl.standardPrincipal(deployer)],
      deployer
    );
    
    expect(deployerAdmin).toBeBool(true);

    const { result: aliceAdmin } = simnet.callReadOnlyFn(
      CONTRACT_NAME,
      "is-user-admin",
      [Cl.standardPrincipal(alice)],
      deployer
    );
    
    expect(aliceAdmin).toBeBool(false);
  });

  it("should return correct best APY", () => {
    const { result } = simnet.callReadOnlyFn(
      CONTRACT_NAME,
      "get-best-apy",
      [],
      deployer
    );
    
    expect(result).toBeUint(1500); // LP Farming strategy has highest APY
  });
});

describe("Yield Vault - Vault Creation & Basic Operations", () => {
  describe("Vault Creation", () => {
    it("should create conservative vault with correct strategy", () => {
      const { result } = simnet.callPublicFn(
        CONTRACT_NAME,
        "create-vault",
        [
          Cl.stringAscii("Conservative Vault"),
          Cl.uint(1), // Conservative risk level
          Cl.uint(1000000), // 1 STX minimum deposit
        ],
        deployer
      );
      
      expect(result).toBeOk(Cl.uint(1));
      
      // Verify vault was created correctly
      const { result: vaultInfo } = simnet.callReadOnlyFn(
        CONTRACT_NAME,
        "get-vault-info",
        [Cl.uint(1)],
        deployer
      );
      
      expect(vaultInfo).toBeSome(
        Cl.tuple({
          "name": Cl.stringAscii("Conservative Vault"),
          "asset": Cl.contractPrincipal(deployer, "stx-token"),
          "total-shares": Cl.uint(0),
          "total-assets": Cl.uint(0),
          "strategy-id": Cl.uint(2), // Conservative uses lending strategy
          "risk-level": Cl.uint(1),
          "min-deposit": Cl.uint(1000000),
          "is-active": Cl.bool(true),
          "created-at": Cl.uint(simnet.blockHeight),
          "last-harvest": Cl.uint(simnet.blockHeight),
        })
      );
    });

    it("should reject vault creation by non-admin", () => {
      const { result } = simnet.callPublicFn(
        CONTRACT_NAME,
        "create-vault",
        [
          Cl.stringAscii("Unauthorized Vault"),
          Cl.uint(1),
          Cl.uint(1000000),
        ],
        alice
      );
      
      expect(result).toBeErr(Cl.uint(200)); // ERR_NOT_AUTHORIZED
    });

    it("should reject invalid risk levels", () => {
      const { result } = simnet.callPublicFn(
        CONTRACT_NAME,
        "create-vault",
        [
          Cl.stringAscii("Invalid Risk Vault"),
          Cl.uint(0), // Invalid risk level
          Cl.uint(1000000),
        ],
        deployer
      );
      
      expect(result).toBeErr(Cl.uint(202)); // ERR_INVALID_AMOUNT
    });
  });

  describe("Basic Deposits", () => {
    beforeEach(() => {
      // Create a test vault before each test
      simnet.callPublicFn(
        CONTRACT_NAME,
        "create-vault",
        [
          Cl.stringAscii("Test Vault"),
          Cl.uint(2), // Balanced risk
          Cl.uint(1000000), // 1 STX minimum
        ],
        deployer
      );
    });

    it("should allow valid deposits and track user position", () => {
      const depositAmount = 5000000; // 5 STX
      
      const { result } = simnet.callPublicFn(
        CONTRACT_NAME,
        "deposit",
        [Cl.uint(1), Cl.uint(depositAmount)],
        alice
      );
      
      expect(result).toBeOk(Cl.uint(depositAmount)); // First deposit gets 1:1 share ratio
      
      // Check user position
      const { result: userPosition } = simnet.callReadOnlyFn(
        CONTRACT_NAME,
        "get-user-position",
        [Cl.uint(1), Cl.standardPrincipal(alice)],
        alice
      );
      
      expect(userPosition).toBeSome(
        Cl.tuple({
          "shares": Cl.uint(depositAmount),
          "deposited-at": Cl.uint(simnet.blockHeight),
          "last-compound": Cl.uint(simnet.blockHeight),
          "total-deposited": Cl.uint(depositAmount),
          "total-withdrawn": Cl.uint(0),
        })
      );
    });

    it("should reject deposits below minimum", () => {
      const { result } = simnet.callPublicFn(
        CONTRACT_NAME,
        "deposit",
        [Cl.uint(1), Cl.uint(500000)], // 0.5 STX, below 1 STX minimum
        alice
      );
      
      expect(result).toBeErr(Cl.uint(206)); // ERR_MINIMUM_DEPOSIT_NOT_MET
    });

    it("should calculate user vault value correctly", () => {
      const depositAmount = 3000000; // 3 STX
      
      simnet.callPublicFn(
        CONTRACT_NAME,
        "deposit",
        [Cl.uint(1), Cl.uint(depositAmount)],
        alice
      );
      
      const { result } = simnet.callReadOnlyFn(
        CONTRACT_NAME,
        "get-user-vault-value",
        [Cl.uint(1), Cl.standardPrincipal(alice)],
        alice
      );
      
      expect(result).toBeUint(depositAmount);
    });
  });

  describe("Basic Withdrawals", () => {
    beforeEach(() => {
      // Create vault and make initial deposit
      simnet.callPublicFn(
        CONTRACT_NAME,
        "create-vault",
        [
          Cl.stringAscii("Test Vault"),
          Cl.uint(2),
          Cl.uint(1000000),
        ],
        deployer
      );
      
      simnet.callPublicFn(
        CONTRACT_NAME,
        "deposit",
        [Cl.uint(1), Cl.uint(5000000)], // 5 STX
        alice
      );
    });

    it("should allow partial withdrawals with correct fees", () => {
      const withdrawShares = 2000000; // 2 STX worth of shares
      const platformFeeRate = 50; // 0.5%
      const expectedFee = Math.floor((withdrawShares * platformFeeRate) / 10000);
      const expectedWithdrawal = withdrawShares - expectedFee;
      
      const { result } = simnet.callPublicFn(
        CONTRACT_NAME,
        "withdraw",
        [Cl.uint(1), Cl.uint(withdrawShares)],
        alice
      );
      
      expect(result).toBeOk(Cl.uint(expectedWithdrawal));
    });

    it("should allow full withdrawals and remove position", () => {
      const totalShares = 5000000;
      const platformFeeRate = 50;
      const expectedFee = Math.floor((totalShares * platformFeeRate) / 10000);
      const expectedWithdrawal = totalShares - expectedFee;
      
      const { result } = simnet.callPublicFn(
        CONTRACT_NAME,
        "withdraw",
        [Cl.uint(1), Cl.uint(totalShares)],
        alice
      );
      
      expect(result).toBeOk(Cl.uint(expectedWithdrawal));
      
      // Position should be deleted after full withdrawal
      const { result: userPosition } = simnet.callReadOnlyFn(
        CONTRACT_NAME,
        "get-user-position",
        [Cl.uint(1), Cl.standardPrincipal(alice)],
        alice
      );
      
      expect(userPosition).toBeNone();
    });

    it("should reject withdrawals exceeding user shares", () => {
      const { result } = simnet.callPublicFn(
        CONTRACT_NAME,
        "withdraw",
        [Cl.uint(1), Cl.uint(10000000)], // More than deposited
        alice
      );
      
      expect(result).toBeErr(Cl.uint(207)); // ERR_WITHDRAWAL_TOO_LARGE
    });

    it("should reject withdrawals from users with no position", () => {
      const { result } = simnet.callPublicFn(
        CONTRACT_NAME,
        "withdraw",
        [Cl.uint(1), Cl.uint(1000000)],
        bob // Bob never deposited
      );
      
      expect(result).toBeErr(Cl.uint(201)); // ERR_INSUFFICIENT_BALANCE
    });
  });
});
