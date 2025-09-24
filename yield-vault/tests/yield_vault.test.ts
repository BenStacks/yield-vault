
import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const alice = accounts.get("wallet_1")!;

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
