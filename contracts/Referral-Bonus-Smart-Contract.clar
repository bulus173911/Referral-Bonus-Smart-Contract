(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-insufficient-balance (err u103))
(define-constant err-invalid-status (err u104))
(define-constant err-unauthorized (err u105))
(define-constant err-invalid-amount (err u106))
(define-constant err-referral-not-found (err u107))
(define-constant err-hire-already-confirmed (err u108))
(define-constant err-hire-not-confirmed (err u109))
(define-constant err-bonus-already-paid (err u110))

(define-data-var next-referral-id uint u1)
(define-data-var next-hire-id uint u1)
(define-data-var contract-balance uint u0)
(define-data-var total-bonuses-paid uint u0)
(define-data-var referral-bonus-amount uint u1000000)
(define-data-var milestone-tier-1-threshold uint u3)
(define-data-var milestone-tier-2-threshold uint u10)
(define-data-var milestone-tier-3-threshold uint u25)
(define-data-var milestone-tier-1-multiplier uint u150)
(define-data-var milestone-tier-2-multiplier uint u200)
(define-data-var milestone-tier-3-multiplier uint u300)

(define-map referrals
    { referral-id: uint }
    {
        referrer: principal,
        candidate: principal,
        position: (string-ascii 100),
        bonus-amount: uint,
        created-at: uint,
        status: (string-ascii 20),
    }
)

(define-map hires
    { hire-id: uint }
    {
        referral-id: uint,
        hiring-manager: principal,
        candidate: principal,
        position: (string-ascii 100),
        hire-date: uint,
        confirmed: bool,
        bonus-paid: bool,
    }
)

(define-map user-referrals
    { user: principal }
    { referral-ids: (list 100 uint) }
)

(define-map user-hires
    { user: principal }
    { hire-ids: (list 100 uint) }
)

(define-map referrer-stats
    { referrer: principal }
    {
        total-referrals: uint,
        successful-hires: uint,
        total-bonuses-earned: uint,
        milestone-tier: uint,
        milestone-achieved-at: uint,
    }
)

(define-public (submit-referral
        (candidate principal)
        (position (string-ascii 100))
    )
    (let (
            (referral-id (var-get next-referral-id))
            (current-block (unwrap-panic (get-stacks-block-info? time burn-block-height)))
        )
        (asserts! (not (is-eq tx-sender candidate)) err-invalid-status)
        (map-set referrals { referral-id: referral-id } {
            referrer: tx-sender,
            candidate: candidate,
            position: position,
            bonus-amount: (var-get referral-bonus-amount),
            created-at: current-block,
            status: "pending",
        })
        (match (map-get? user-referrals { user: tx-sender })
            existing-referrals (map-set user-referrals { user: tx-sender } { referral-ids: (unwrap!
                (as-max-len?
                    (append (get referral-ids existing-referrals) referral-id)
                    u100
                )
                err-invalid-status
            ) }
            )
            (map-set user-referrals { user: tx-sender } { referral-ids: (list referral-id) })
        )
        (match (map-get? referrer-stats { referrer: tx-sender })
            existing-stats (map-set referrer-stats { referrer: tx-sender } {
                total-referrals: (+ (get total-referrals existing-stats) u1),
                successful-hires: (get successful-hires existing-stats),
                total-bonuses-earned: (get total-bonuses-earned existing-stats),
                milestone-tier: (get milestone-tier existing-stats),
                milestone-achieved-at: (get milestone-achieved-at existing-stats),
            })
            (map-set referrer-stats { referrer: tx-sender } {
                total-referrals: u1,
                successful-hires: u0,
                total-bonuses-earned: u0,
                milestone-tier: u0,
                milestone-achieved-at: u0,
            })
        )
        (var-set next-referral-id (+ referral-id u1))
        (ok referral-id)
    )
)

(define-public (confirm-hire
        (referral-id uint)
        (hiring-manager principal)
    )
    (let (
            (referral (unwrap! (map-get? referrals { referral-id: referral-id })
                err-referral-not-found
            ))
            (hire-id (var-get next-hire-id))
            (current-block (unwrap-panic (get-stacks-block-info? time burn-block-height)))
        )
        (asserts! (is-eq (get status referral) "pending") err-invalid-status)
        (map-set referrals { referral-id: referral-id }
            (merge referral { status: "hired" })
        )
        (map-set hires { hire-id: hire-id } {
            referral-id: referral-id,
            hiring-manager: hiring-manager,
            candidate: (get candidate referral),
            position: (get position referral),
            hire-date: current-block,
            confirmed: true,
            bonus-paid: false,
        })
        (match (map-get? user-hires { user: hiring-manager })
            existing-hires (map-set user-hires { user: hiring-manager } { hire-ids: (unwrap!
                (as-max-len? (append (get hire-ids existing-hires) hire-id) u100)
                err-invalid-status
            ) }
            )
            (map-set user-hires { user: hiring-manager } { hire-ids: (list hire-id) })
        )
        (let (
                (referrer (get referrer referral))
                (existing-stats (default-to {
                    total-referrals: u0,
                    successful-hires: u0,
                    total-bonuses-earned: u0,
                    milestone-tier: u0,
                    milestone-achieved-at: u0,
                }
                    (map-get? referrer-stats { referrer: referrer })
                ))
                (new-hire-count (+ (get successful-hires existing-stats) u1))
                (new-tier (if (>= new-hire-count (var-get milestone-tier-3-threshold))
                    u3
                    (if (>= new-hire-count (var-get milestone-tier-2-threshold))
                        u2
                        (if (>= new-hire-count
                                (var-get milestone-tier-1-threshold)
                            )
                            u1
                            u0
                        )
                    )
                ))
                (milestone-block (unwrap-panic (get-stacks-block-info? time burn-block-height)))
            )
            (map-set referrer-stats { referrer: referrer } {
                total-referrals: (get total-referrals existing-stats),
                successful-hires: new-hire-count,
                total-bonuses-earned: (get total-bonuses-earned existing-stats),
                milestone-tier: new-tier,
                milestone-achieved-at: (if (> new-tier (get milestone-tier existing-stats))
                    milestone-block
                    (get milestone-achieved-at existing-stats)
                ),
            })
        )
        (var-set next-hire-id (+ hire-id u1))
        (ok hire-id)
    )
)

(define-public (pay-referral-bonus (hire-id uint))
    (let (
            (hire (unwrap! (map-get? hires { hire-id: hire-id }) err-not-found))
            (referral (unwrap! (map-get? referrals { referral-id: (get referral-id hire) })
                err-referral-not-found
            ))
            (referrer (get referrer referral))
            (current-referrer-stats (default-to {
                total-referrals: u0,
                successful-hires: u0,
                total-bonuses-earned: u0,
                milestone-tier: u0,
                milestone-achieved-at: u0,
            }
                (map-get? referrer-stats { referrer: referrer })
            ))
            (bonus-multiplier (get-milestone-multiplier (get milestone-tier current-referrer-stats)))
            (bonus-amount (/ (* (get bonus-amount referral) bonus-multiplier) u100))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (get confirmed hire) err-hire-not-confirmed)
        (asserts! (not (get bonus-paid hire)) err-bonus-already-paid)
        (asserts! (>= (var-get contract-balance) bonus-amount)
            err-insufficient-balance
        )
        (try! (stx-transfer? bonus-amount tx-sender referrer))
        (map-set hires { hire-id: hire-id } (merge hire { bonus-paid: true }))
        (var-set contract-balance (- (var-get contract-balance) bonus-amount))
        (var-set total-bonuses-paid (+ (var-get total-bonuses-paid) bonus-amount))
        (map-set referrer-stats { referrer: referrer } {
            total-referrals: (get total-referrals current-referrer-stats),
            successful-hires: (get successful-hires current-referrer-stats),
            total-bonuses-earned: (+ (get total-bonuses-earned current-referrer-stats) bonus-amount),
            milestone-tier: (get milestone-tier current-referrer-stats),
            milestone-achieved-at: (get milestone-achieved-at current-referrer-stats),
        })
        (ok bonus-amount)
    )
)

(define-public (fund-contract)
    (let ((amount (stx-get-balance tx-sender)))
        (asserts! (> amount u0) err-invalid-amount)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set contract-balance (+ (var-get contract-balance) amount))
        (ok amount)
    )
)

(define-public (withdraw-funds (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= amount (var-get contract-balance)) err-insufficient-balance)
        (try! (as-contract (stx-transfer? amount tx-sender contract-owner)))
        (var-set contract-balance (- (var-get contract-balance) amount))
        (ok amount)
    )
)

(define-public (update-bonus-amount (new-amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> new-amount u0) err-invalid-amount)
        (var-set referral-bonus-amount new-amount)
        (ok new-amount)
    )
)

(define-public (cancel-referral (referral-id uint))
    (let ((referral (unwrap! (map-get? referrals { referral-id: referral-id })
            err-referral-not-found
        )))
        (asserts! (is-eq tx-sender (get referrer referral)) err-unauthorized)
        (asserts! (is-eq (get status referral) "pending") err-invalid-status)
        (map-set referrals { referral-id: referral-id }
            (merge referral { status: "cancelled" })
        )
        (ok true)
    )
)

(define-read-only (get-referral (referral-id uint))
    (map-get? referrals { referral-id: referral-id })
)

(define-read-only (get-hire (hire-id uint))
    (map-get? hires { hire-id: hire-id })
)

(define-read-only (get-user-referrals (user principal))
    (default-to { referral-ids: (list) } (map-get? user-referrals { user: user }))
)

(define-read-only (get-user-hires (user principal))
    (default-to { hire-ids: (list) } (map-get? user-hires { user: user }))
)

(define-read-only (get-referrer-stats (referrer principal))
    (default-to {
        total-referrals: u0,
        successful-hires: u0,
        total-bonuses-earned: u0,
        milestone-tier: u0,
        milestone-achieved-at: u0,
    }
        (map-get? referrer-stats { referrer: referrer })
    )
)

(define-read-only (get-contract-balance)
    (var-get contract-balance)
)

(define-read-only (get-total-bonuses-paid)
    (var-get total-bonuses-paid)
)

(define-read-only (get-current-bonus-amount)
    (var-get referral-bonus-amount)
)

(define-read-only (get-contract-owner)
    contract-owner
)

(define-read-only (get-next-referral-id)
    (var-get next-referral-id)
)

(define-read-only (get-next-hire-id)
    (var-get next-hire-id)
)

(define-private (get-milestone-multiplier (tier uint))
    (if (is-eq tier u3)
        (var-get milestone-tier-3-multiplier)
        (if (is-eq tier u2)
            (var-get milestone-tier-2-multiplier)
            (if (is-eq tier u1)
                (var-get milestone-tier-1-multiplier)
                u100
            )
        )
    )
)

(define-public (update-milestone-thresholds
        (tier-1-threshold uint)
        (tier-2-threshold uint)
        (tier-3-threshold uint)
    )
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts!
            (and
                (> tier-1-threshold u0)
                (> tier-2-threshold tier-1-threshold)
                (> tier-3-threshold tier-2-threshold)
            )
            err-invalid-amount
        )
        (var-set milestone-tier-1-threshold tier-1-threshold)
        (var-set milestone-tier-2-threshold tier-2-threshold)
        (var-set milestone-tier-3-threshold tier-3-threshold)
        (ok true)
    )
)

(define-public (update-milestone-multipliers
        (tier-1-multiplier uint)
        (tier-2-multiplier uint)
        (tier-3-multiplier uint)
    )
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts!
            (and
                (> tier-1-multiplier u100)
                (> tier-2-multiplier tier-1-multiplier)
                (> tier-3-multiplier tier-2-multiplier)
            )
            err-invalid-amount
        )
        (var-set milestone-tier-1-multiplier tier-1-multiplier)
        (var-set milestone-tier-2-multiplier tier-2-multiplier)
        (var-set milestone-tier-3-multiplier tier-3-multiplier)
        (ok true)
    )
)

(define-read-only (get-milestone-info (referrer principal))
    (let ((stats (get-referrer-stats referrer)))
        {
            current-tier: (get milestone-tier stats),
            next-tier-hires-needed: (-
                (if (is-eq (get milestone-tier stats) u0)
                    (var-get milestone-tier-1-threshold)
                    (if (is-eq (get milestone-tier stats) u1)
                        (var-get milestone-tier-2-threshold)
                        (if (is-eq (get milestone-tier stats) u2)
                            (var-get milestone-tier-3-threshold)
                            u0
                        )
                    )
                )
                (get successful-hires stats)
            ),
            current-multiplier: (get-milestone-multiplier (get milestone-tier stats)),
            milestone-achieved-at: (get milestone-achieved-at stats),
        }
    )
)

(define-read-only (get-milestone-config)
    {
        tier-1-threshold: (var-get milestone-tier-1-threshold),
        tier-2-threshold: (var-get milestone-tier-2-threshold),
        tier-3-threshold: (var-get milestone-tier-3-threshold),
        tier-1-multiplier: (var-get milestone-tier-1-multiplier),
        tier-2-multiplier: (var-get milestone-tier-2-multiplier),
        tier-3-multiplier: (var-get milestone-tier-3-multiplier),
    }
)

(define-read-only (get-contract-stats)
    {
        total-referrals: (- (var-get next-referral-id) u1),
        total-hires: (- (var-get next-hire-id) u1),
        total-bonuses-paid: (var-get total-bonuses-paid),
        contract-balance: (var-get contract-balance),
        current-bonus-amount: (var-get referral-bonus-amount),
    }
)
