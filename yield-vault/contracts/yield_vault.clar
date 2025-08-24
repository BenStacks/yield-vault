;; Yield-Vault - Yield Aggregator Smart Contract
;; Automatically finds and compounds the best yield opportunities across DeFi protocols

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u200))
(define-constant ERR_INSUFFICIENT_BALANCE (err u201))
(define-constant ERR_INVALID_AMOUNT (err u202))
(define-constant ERR_VAULT_NOT_FOUND (err u203))
(define-constant ERR_STRATEGY_NOT_FOUND (err u204))
(define-constant ERR_VAULT_PAUSED (err u205))
(define-constant ERR_MINIMUM_DEPOSIT_NOT_MET (err u206))
(define-constant ERR_WITHDRAWAL_TOO_LARGE (err u207))
(define-constant ERR_STRATEGY_INACTIVE (err u208))
(define-constant ERR_REBALANCE_TOO_FREQUENT (err u209))
(define-constant ERR_INVALID_VAULT_ID (err u210))

;; Data Variables
(define-data-var total-value-locked uint u0)
(define-data-var vault-counter uint u0)
(define-data-var strategy-counter uint u0)
(define-data-var platform-fee-rate uint u50) ;; 0.5% platform fee
(define-data-var performance-fee-rate uint u1000) ;; 10% performance fee
(define-data-var treasury principal CONTRACT_OWNER)
(define-data-var emergency-pause bool false)

;; Data Maps
(define-map vaults
    uint
    {
        name: (string-ascii 64),
        asset: principal,
        total-shares: uint,
        total-assets: uint,
        strategy-id: uint,
        risk-level: uint, ;; 1=conservative, 2=balanced, 3=aggressive
        min-deposit: uint,
        is-active: bool,
        created-at: uint,
        last-harvest: uint,
    }
)

(define-map user-positions
    {
        vault-id: uint,
        user: principal,
    }
    {
        shares: uint,
        deposited-at: uint,
        last-compound: uint,
        total-deposited: uint,
        total-withdrawn: uint,
    }
)

(define-map yield-strategies
    uint
    {
        name: (string-ascii 64),
        protocol: (string-ascii 32),
        apy: uint, ;; APY in basis points (e.g., 1000 = 10%)
        tvl-capacity: uint,
        current-tvl: uint,
        risk-score: uint, ;; 1-10 risk rating
        is-active: bool,
        contract-address: principal,
        last-updated: uint,
    }
)

(define-map vault-strategies
    uint
    (list 5 uint) ;; Up to 5 strategies per vault
)

(define-map user-vault-list
    principal
    (list 20 uint) ;; Track user's vaults
)

(define-map strategy-allocations
    {
        vault-id: uint,
        strategy-id: uint,
    }
    uint ;; Percentage allocation (0-10000 basis points)
)

(define-map admin-roles
    principal
    bool
)

;; Initialize default strategies
(map-set yield-strategies u1 {
    name: "STX-Staking-Strategy",
    protocol: "stx-vault",
    apy: u1200, ;; 12% APY
    tvl-capacity: u100000000000, ;; 100k STX capacity
    current-tvl: u0,
    risk-score: u3,
    is-active: true,
    contract-address: CONTRACT_OWNER, ;; Replace with actual staking contract
    last-updated: stacks-block-height,
})

(map-set yield-strategies u2 {
    name: "Lending-Protocol-Strategy",
    protocol: "arkadiko",
    apy: u800, ;; 8% APY
    tvl-capacity: u50000000000, ;; 50k STX capacity
    current-tvl: u0,
    risk-score: u5,
    is-active: true,
    contract-address: CONTRACT_OWNER, ;; Replace with lending contract
    last-updated: stacks-block-height,
})

(map-set yield-strategies u3 {
    name: "LP-Farming-Strategy",
    protocol: "alex",
    apy: u1500, ;; 15% APY
    tvl-capacity: u25000000000, ;; 25k STX capacity
    current-tvl: u0,
    risk-score: u7,
    is-active: true,
    contract-address: CONTRACT_OWNER, ;; Replace with LP contract
    last-updated: stacks-block-height,
})

;; Set initial strategy counter
(var-set strategy-counter u3)

;; Private Functions
(define-private (is-admin (user principal))
    (or
        (is-eq user CONTRACT_OWNER)
        (default-to false (map-get? admin-roles user))
    )
)

(define-private (calculate-shares
        (assets uint)
        (total-assets uint)
        (total-shares uint)
    )
    (if (is-eq total-shares u0)
        assets ;; First deposit gets 1:1 share ratio
        (/ (* assets total-shares) total-assets)
    )
)

(define-private (calculate-assets
        (shares uint)
        (total-assets uint)
        (total-shares uint)
    )
    (if (is-eq total-shares u0)
        u0
        (/ (* shares total-assets) total-shares)
    )
)

(define-private (get-best-strategy (risk-level uint))
    (let (
            (conservative-strategies (list u2)) ;; Lower risk strategies
            (balanced-strategies (list u1 u2)) ;; Mixed risk
            (aggressive-strategies (list u1 u2 u3)) ;; All strategies
        )
        (if (is-eq risk-level u1)
            (unwrap-panic (element-at conservative-strategies u0))
            (if (is-eq risk-level u2)
                (unwrap-panic (element-at balanced-strategies u0))
                (unwrap-panic (element-at aggressive-strategies u0))
            )
        )
    )
)

(define-private (calculate-vault-yield (vault-id uint))
    (let (
            (vault-data (unwrap! (map-get? vaults vault-id) u0))
            (strategy-id (get strategy-id vault-data))
            (strategy-data (unwrap! (map-get? yield-strategies strategy-id) u0))
        )
        (get apy strategy-data)
    )
)

(define-private (update-user-vault-list
        (user principal)
        (vault-id uint)
    )
    (let ((current-list (default-to (list) (map-get? user-vault-list user))))
        (map-set user-vault-list user
            (unwrap-panic (as-max-len? (append current-list vault-id) u20))
        )
    )
)

(define-private (compound-vault-earnings (vault-id uint))
    (let (
            (vault-data (unwrap! (map-get? vaults vault-id) false))
            (yield-rate (calculate-vault-yield vault-id))
            (blocks-since-harvest (- stacks-block-height (get last-harvest vault-data)))
            (yield-earned (/ (* (get total-assets vault-data) yield-rate blocks-since-harvest)
                u5256000
            ))
            ;; Approx blocks per year
        )
        (if (> yield-earned u0)
            (begin
                (map-set vaults vault-id
                    (merge vault-data {
                        total-assets: (+ (get total-assets vault-data) yield-earned),
                        last-harvest: stacks-block-height,
                    })
                )
                true
            )
            false
        )
    )
)

;; Helper function to find the maximum of two numbers
(define-private (max
        (a uint)
        (b uint)
    )
    (if (> a b)
        a
        b
    )
)

;; Public Functions

;; Create a new yield vault
(define-public (create-vault
        (name (string-ascii 64))
        (risk-level uint)
        (min-deposit uint)
    )
    (let (
            (vault-id (+ (var-get vault-counter) u1))
            (best-strategy (get-best-strategy risk-level))
        )
        (asserts! (is-admin tx-sender) ERR_NOT_AUTHORIZED)
        (asserts! (not (var-get emergency-pause)) ERR_VAULT_PAUSED)
        (asserts! (and (>= risk-level u1) (<= risk-level u3)) ERR_INVALID_AMOUNT)
        ;; Create vault
        (map-set vaults vault-id {
            name: name,
            asset: .stx-token, ;; Default to STX
            total-shares: u0,
            total-assets: u0,
            strategy-id: best-strategy,
            risk-level: risk-level,
            min-deposit: min-deposit,
            is-active: true,
            created-at: stacks-block-height,
            last-harvest: stacks-block-height,
        })
        ;; Set default strategy allocation
        (map-set strategy-allocations {
            vault-id: vault-id,
            strategy-id: best-strategy,
        }
            u10000
        )
        ;; Update counter
        (var-set vault-counter vault-id)
        (ok vault-id)
    )
)

;; Deposit assets into a vault
(define-public (deposit
        (vault-id uint)
        (amount uint)
    )
    (let (
            (vault-data (unwrap! (map-get? vaults vault-id) ERR_VAULT_NOT_FOUND))
            (user tx-sender)
            (shares-to-mint (calculate-shares amount (get total-assets vault-data)
                (get total-shares vault-data)
            ))
            (current-position (default-to {
                shares: u0,
                deposited-at: stacks-block-height,
                last-compound: stacks-block-height,
                total-deposited: u0,
                total-withdrawn: u0,
            }
                (map-get? user-positions {
                    vault-id: vault-id,
                    user: user,
                })
            ))
        )
        (asserts! (not (var-get emergency-pause)) ERR_VAULT_PAUSED)
        (asserts! (get is-active vault-data) ERR_VAULT_PAUSED)
        (asserts! (>= amount (get min-deposit vault-data))
            ERR_MINIMUM_DEPOSIT_NOT_MET
        )
        ;; Compound existing earnings before new deposit
        (compound-vault-earnings vault-id)
        ;; Transfer STX from user to contract
        (try! (stx-transfer? amount user (as-contract tx-sender)))
        ;; Update user position
        (map-set user-positions {
            vault-id: vault-id,
            user: user,
        } {
            shares: (+ (get shares current-position) shares-to-mint),
            deposited-at: (get deposited-at current-position),
            last-compound: stacks-block-height,
            total-deposited: (+ (get total-deposited current-position) amount),
            total-withdrawn: (get total-withdrawn current-position),
        })
        ;; Update vault totals
        (map-set vaults vault-id
            (merge vault-data {
                total-shares: (+ (get total-shares vault-data) shares-to-mint),
                total-assets: (+ (get total-assets vault-data) amount),
            })
        )
        ;; Update global TVL
        (var-set total-value-locked (+ (var-get total-value-locked) amount))
        ;; Add vault to user's list
        (update-user-vault-list user vault-id)
        (ok shares-to-mint)
    )
)

;; Withdraw assets from vault
(define-public (withdraw
        (vault-id uint)
        (shares uint)
    )
    (let (
            (vault-data (unwrap! (map-get? vaults vault-id) ERR_VAULT_NOT_FOUND))
            (user tx-sender)
            (user-position (unwrap!
                (map-get? user-positions {
                    vault-id: vault-id,
                    user: user,
                })
                ERR_INSUFFICIENT_BALANCE
            ))
            (user-shares (get shares user-position))
            (assets-to-withdraw (calculate-assets shares (get total-assets vault-data)
                (get total-shares vault-data)
            ))
            (platform-fee (/ (* assets-to-withdraw (var-get platform-fee-rate)) u10000))
            (net-withdrawal (- assets-to-withdraw platform-fee))
        )
        (asserts! (not (var-get emergency-pause)) ERR_VAULT_PAUSED)
        (asserts! (<= shares user-shares) ERR_WITHDRAWAL_TOO_LARGE)
        (asserts! (> shares u0) ERR_INVALID_AMOUNT)
        ;; Compound earnings before withdrawal
        (compound-vault-earnings vault-id)
        ;; Update user position
        (if (is-eq shares user-shares)
            ;; Full withdrawal - remove position
            (map-delete user-positions {
                vault-id: vault-id,
                user: user,
            })
            ;; Partial withdrawal - update position
            (map-set user-positions {
                vault-id: vault-id,
                user: user,
            }
                (merge user-position {
                    shares: (- user-shares shares),
                    total-withdrawn: (+ (get total-withdrawn user-position) net-withdrawal),
                })
            )
        )
        ;; Update vault totals
        (map-set vaults vault-id
            (merge vault-data {
                total-shares: (- (get total-shares vault-data) shares),
                total-assets: (- (get total-assets vault-data) assets-to-withdraw),
            })
        )
        ;; Transfer assets to user (minus fee)
        (try! (as-contract (stx-transfer? net-withdrawal tx-sender user)))
        ;; Transfer fee to treasury
        (if (> platform-fee u0)
            (try! (as-contract (stx-transfer? platform-fee tx-sender (var-get treasury))))
            true
        )
        ;; Update global TVL
        (var-set total-value-locked
            (- (var-get total-value-locked) assets-to-withdraw)
        )
        (ok net-withdrawal)
    )
)

;; Compound all earnings in a vault
(define-public (harvest-vault (vault-id uint))
    (let ((vault-data (unwrap! (map-get? vaults vault-id) ERR_VAULT_NOT_FOUND)))
        (asserts! (not (var-get emergency-pause)) ERR_VAULT_PAUSED)
        (asserts! (get is-active vault-data) ERR_VAULT_PAUSED)
        ;; Compound earnings
        (asserts! (compound-vault-earnings vault-id) (ok false))
        (ok true)
    )
)

;; Rebalance vault strategies (admin only)
(define-public (rebalance-vault
        (vault-id uint)
        (new-strategy-id uint)
    )
    (let (
            (vault-data (unwrap! (map-get? vaults vault-id) ERR_VAULT_NOT_FOUND))
            (strategy-data (unwrap! (map-get? yield-strategies new-strategy-id)
                ERR_STRATEGY_NOT_FOUND
            ))
        )
        (asserts! (is-admin tx-sender) ERR_NOT_AUTHORIZED)
        (asserts! (get is-active strategy-data) ERR_STRATEGY_INACTIVE)
        ;; Harvest current position before rebalancing
        (try! (harvest-vault vault-id))
        ;; Update vault strategy
        (map-set vaults vault-id
            (merge vault-data { strategy-id: new-strategy-id })
        )
        ;; Update strategy allocation
        (map-set strategy-allocations {
            vault-id: vault-id,
            strategy-id: new-strategy-id,
        }
            u10000
        )
        (ok true)
    )
)

;; Admin Functions

;; Add or update yield strategy
(define-public (add-strategy
        (name (string-ascii 64))
        (protocol (string-ascii 32))
        (apy uint)
        (capacity uint)
        (risk-score uint)
        (contract-addr principal)
    )
    (let ((strategy-id (+ (var-get strategy-counter) u1)))
        (asserts! (is-admin tx-sender) ERR_NOT_AUTHORIZED)
        (map-set yield-strategies strategy-id {
            name: name,
            protocol: protocol,
            apy: apy,
            tvl-capacity: capacity,
            current-tvl: u0,
            risk-score: risk-score,
            is-active: true,
            contract-address: contract-addr,
            last-updated: stacks-block-height,
        })
        (var-set strategy-counter strategy-id)
        (ok strategy-id)
    )
)

;; Update strategy APY
(define-public (update-strategy-apy
        (strategy-id uint)
        (new-apy uint)
    )
    (let ((strategy-data (unwrap! (map-get? yield-strategies strategy-id) ERR_STRATEGY_NOT_FOUND)))
        (asserts! (is-admin tx-sender) ERR_NOT_AUTHORIZED)
        (map-set yield-strategies strategy-id
            (merge strategy-data {
                apy: new-apy,
                last-updated: stacks-block-height,
            })
        )
        (ok new-apy)
    )
)

;; Set platform fees
(define-public (set-platform-fee (new-fee uint))
    (begin
        (asserts! (is-admin tx-sender) ERR_NOT_AUTHORIZED)
        (asserts! (<= new-fee u1000) ERR_INVALID_AMOUNT) ;; Max 10% fee
        (var-set platform-fee-rate new-fee)
        (ok new-fee)
    )
)

;; Add admin role
(define-public (add-admin (new-admin principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (map-set admin-roles new-admin true)
        (ok true)
    )
)

;; Emergency pause
(define-public (toggle-emergency-pause)
    (begin
        (asserts! (is-admin tx-sender) ERR_NOT_AUTHORIZED)
        (var-set emergency-pause (not (var-get emergency-pause)))
        (ok (var-get emergency-pause))
    )
)

;; Read-only Functions

;; Get vault information
(define-read-only (get-vault-info (vault-id uint))
    (map-get? vaults vault-id)
)

;; Get user position
(define-read-only (get-user-position
        (vault-id uint)
        (user principal)
    )
    (map-get? user-positions {
        vault-id: vault-id,
        user: user,
    })
)

;; Get user's vault value
(define-read-only (get-user-vault-value
        (vault-id uint)
        (user principal)
    )
    (let (
            (vault-data (unwrap! (map-get? vaults vault-id) u0))
            (user-position (unwrap!
                (map-get? user-positions {
                    vault-id: vault-id,
                    user: user,
                })
                u0
            ))
            (user-shares (get shares user-position))
        )
        (calculate-assets user-shares (get total-assets vault-data)
            (get total-shares vault-data)
        )
    )
)

;; Get strategy information
(define-read-only (get-strategy-info (strategy-id uint))
    (map-get? yield-strategies strategy-id)
)

;; Get platform statistics
(define-read-only (get-platform-stats)
    {
        total-value-locked: (var-get total-value-locked),
        total-vaults: (var-get vault-counter),
        total-strategies: (var-get strategy-counter),
        platform-fee-rate: (var-get platform-fee-rate),
        emergency-pause: (var-get emergency-pause),
    }
)

;; Get user's all vaults
(define-read-only (get-user-vaults (user principal))
    (default-to (list) (map-get? user-vault-list user))
)

;; Get best APY available
(define-read-only (get-best-apy)
    (let (
            (strategy1 (unwrap-panic (map-get? yield-strategies u1)))
            (strategy2 (unwrap-panic (map-get? yield-strategies u2)))
            (strategy3 (unwrap-panic (map-get? yield-strategies u3)))
        )
        (max (max (get apy strategy1) (get apy strategy2)) (get apy strategy3))
    )
)

;; Check if user is admin
(define-read-only (is-user-admin (user principal))
    (is-admin user)
)
