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
