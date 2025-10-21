;; title: referral-bonus
;; version: 1.0.0
;; summary: Advanced Referral Bonus Smart Contract with Analytics
;; description: A comprehensive referral system that tracks bonuses, analytics, and provides reward distribution

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-USER-NOT-FOUND (err u102))
(define-constant ERR-SELF-REFERRAL (err u103))
(define-constant ERR-ALREADY-REFERRED (err u104))
(define-constant ERR-INSUFFICIENT-BALANCE (err u105))
(define-constant ERR-INVALID-PERCENTAGE (err u106))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MIN-REFERRAL-BONUS u10) ;; Minimum bonus in microSTX
(define-constant MAX-REFERRAL-BONUS u1000000) ;; Maximum bonus in microSTX
(define-constant DEFAULT-BONUS-PERCENTAGE u5) ;; 5% default bonus

;; Data variables
(define-data-var contract-enabled bool true)
(define-data-var total-referrals uint u0)
(define-data-var total-bonus-distributed uint u0)
(define-data-var bonus-percentage uint DEFAULT-BONUS-PERCENTAGE)
(define-data-var contract-balance uint u0)

;; Data maps
(define-map users
  { user: principal }
  {
    referrer: (optional principal),
    total-earned: uint,
    referral-count: uint,
    join-block: uint,
    is-active: bool
  }
)

(define-map referral-bonds
  { referrer: principal, referee: principal }
  {
    bonus-amount: uint,
    created-at: uint,
    status: (string-ascii 20)
  }
)

(define-map analytics-daily
  { date: uint }
  {
    new-users: uint,
    bonuses-paid: uint,
    total-volume: uint
  }
)

(define-map user-analytics
  { user: principal }
  {
    last-activity: uint,
    total-transactions: uint,
    referral-tier: uint,
    performance-score: uint
  }
)

;; Public functions

;; Initialize or update user profile
(define-public (register-user (referrer (optional principal)))
  (let
    (
      (current-block stacks-block-height)
      (today (get-today))
      (existing-user (map-get? users { user: tx-sender }))
    )
    (asserts! (var-get contract-enabled) ERR-NOT-AUTHORIZED)
    (asserts! (is-none existing-user) ERR-ALREADY-REFERRED)
    
    ;; Validate referrer if provided
    (match referrer
      some-referrer
        (begin
          (asserts! (not (is-eq tx-sender some-referrer)) ERR-SELF-REFERRAL)
          (asserts! (is-some (map-get? users { user: some-referrer })) ERR-USER-NOT-FOUND)
        )
      true
    )
    
    ;; Register the user
    (map-set users
      { user: tx-sender }
      {
        referrer: referrer,
        total-earned: u0,
        referral-count: u0,
        join-block: current-block,
        is-active: true
      }
    )
    
    ;; Initialize user analytics
    (map-set user-analytics
      { user: tx-sender }
      {
        last-activity: current-block,
        total-transactions: u0,
        referral-tier: u1,
        performance-score: u100
      }
    )
    
    ;; Update daily analytics
    (update-daily-analytics today u1 u0 u0)
    
    ;; If referred, create referral bond and update referrer stats
    (match referrer
      some-referrer
        (begin
          (map-set referral-bonds
            { referrer: some-referrer, referee: tx-sender }
            {
              bonus-amount: u0,
              created-at: current-block,
              status: "active"
            }
          )
          (update-referrer-stats some-referrer)
          (var-set total-referrals (+ (var-get total-referrals) u1))
        )
      true
    )
    
    (ok true)
  )
)

;; Process referral bonus
(define-public (process-referral-bonus (referee principal) (transaction-amount uint))
  (let
    (
      (user-data (unwrap! (map-get? users { user: referee }) ERR-USER-NOT-FOUND))
      (referrer-principal (unwrap! (get referrer user-data) ERR-USER-NOT-FOUND))
      (bonus-amount (calculate-bonus transaction-amount))
      (today (get-today))
    )
    (asserts! (var-get contract-enabled) ERR-NOT-AUTHORIZED)
    (asserts! (> transaction-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= (var-get contract-balance) bonus-amount) ERR-INSUFFICIENT-BALANCE)
    
    ;; Update referrer earnings
    (update-user-earnings referrer-principal bonus-amount)
    
    ;; Update referral bond
    (map-set referral-bonds
      { referrer: referrer-principal, referee: referee }
      (merge 
        (unwrap-panic (map-get? referral-bonds { referrer: referrer-principal, referee: referee }))
        { bonus-amount: (+ (get bonus-amount 
          (unwrap-panic (map-get? referral-bonds { referrer: referrer-principal, referee: referee }))) 
          bonus-amount) }
      )
    )
    
    ;; Update contract state
    (var-set total-bonus-distributed (+ (var-get total-bonus-distributed) bonus-amount))
    (var-set contract-balance (- (var-get contract-balance) bonus-amount))
    
    ;; Update analytics
    (update-daily-analytics today u0 bonus-amount transaction-amount)
    (update-user-activity referee transaction-amount)
    
    (ok bonus-amount)
  )
)

;; Admin function to fund contract
(define-public (fund-contract (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set contract-balance (+ (var-get contract-balance) amount))
    (ok true)
  )
)

;; Admin function to withdraw from contract
(define-public (withdraw-funds (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= (var-get contract-balance) amount) ERR-INSUFFICIENT-BALANCE)
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT-OWNER)))
    (var-set contract-balance (- (var-get contract-balance) amount))
    (ok true)
  )
)

;; Admin function to update bonus percentage
(define-public (set-bonus-percentage (percentage uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (and (<= percentage u50) (>= percentage u1)) ERR-INVALID-PERCENTAGE)
    (var-set bonus-percentage percentage)
    (ok true)
  )
)

;; Admin function to toggle contract
(define-public (toggle-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-enabled (not (var-get contract-enabled)))
    (ok (var-get contract-enabled))
  )
)

;; Read-only functions

;; Get user information
(define-read-only (get-user-info (user principal))
  (map-get? users { user: user })
)

;; Get user analytics
(define-read-only (get-user-analytics (user principal))
  (map-get? user-analytics { user: user })
)

;; Get referral bond information
(define-read-only (get-referral-bond (referrer principal) (referee principal))
  (map-get? referral-bonds { referrer: referrer, referee: referee })
)

;; Get daily analytics
(define-read-only (get-daily-analytics (date uint))
  (map-get? analytics-daily { date: date })
)

;; Get contract statistics
(define-read-only (get-contract-stats)
  {
    total-referrals: (var-get total-referrals),
    total-bonus-distributed: (var-get total-bonus-distributed),
    contract-balance: (var-get contract-balance),
    bonus-percentage: (var-get bonus-percentage),
    is-enabled: (var-get contract-enabled)
  }
)

;; Calculate user referral tier based on performance
(define-read-only (get-user-tier (user principal))
  (let
    (
      (user-data (map-get? users { user: user }))
      (analytics-data (map-get? user-analytics { user: user }))
    )
    (match user-data
      some-user
        (let
          (
            (referral-count (get referral-count some-user))
            (total-earned (get total-earned some-user))
          )
          (if (and (>= referral-count u50) (>= total-earned u100000))
            u5 ;; Diamond tier
            (if (and (>= referral-count u25) (>= total-earned u50000))
              u4 ;; Platinum tier
              (if (and (>= referral-count u10) (>= total-earned u20000))
                u3 ;; Gold tier
                (if (and (>= referral-count u5) (>= total-earned u5000))
                  u2 ;; Silver tier
                  u1 ;; Bronze tier
                )
              )
            )
          )
        )
      u1
    )
  )
)

;; Private functions

;; Calculate bonus based on transaction amount
(define-private (calculate-bonus (amount uint))
  (let
    (
      (percentage (var-get bonus-percentage))
      (calculated-bonus (/ (* amount percentage) u100))
    )
    (if (< calculated-bonus MIN-REFERRAL-BONUS)
      MIN-REFERRAL-BONUS
      (if (> calculated-bonus MAX-REFERRAL-BONUS)
        MAX-REFERRAL-BONUS
        calculated-bonus
      )
    )
  )
)

;; Update user earnings
(define-private (update-user-earnings (user principal) (amount uint))
  (match (map-get? users { user: user })
    some-user
      (map-set users
        { user: user }
        (merge some-user { total-earned: (+ (get total-earned some-user) amount) })
      )
    false
  )
)

;; Update referrer statistics
(define-private (update-referrer-stats (referrer principal))
  (match (map-get? users { user: referrer })
    some-referrer
      (map-set users
        { user: referrer }
        (merge some-referrer { referral-count: (+ (get referral-count some-referrer) u1) })
      )
    false
  )
)

;; Update daily analytics
(define-private (update-daily-analytics (date uint) (new-users uint) (bonuses uint) (volume uint))
  (let
    (
      (existing-data (default-to 
        { new-users: u0, bonuses-paid: u0, total-volume: u0 }
        (map-get? analytics-daily { date: date })
      ))
    )
    (map-set analytics-daily
      { date: date }
      {
        new-users: (+ (get new-users existing-data) new-users),
        bonuses-paid: (+ (get bonuses-paid existing-data) bonuses),
        total-volume: (+ (get total-volume existing-data) volume)
      }
    )
  )
)

;; Update user activity
(define-private (update-user-activity (user principal) (transaction-amount uint))
  (match (map-get? user-analytics { user: user })
    some-analytics
      (let
        (
          (new-tx-count (+ (get total-transactions some-analytics) u1))
          (new-score (calculate-performance-score user new-tx-count transaction-amount))
          (new-tier (get-user-tier user))
        )
        (map-set user-analytics
          { user: user }
          {
            last-activity: stacks-block-height,
            total-transactions: new-tx-count,
            referral-tier: new-tier,
            performance-score: new-score
          }
        )
      )
    false
  )
)

;; Calculate performance score
(define-private (calculate-performance-score (user principal) (tx-count uint) (amount uint))
  (let
    (
      (user-data (map-get? users { user: user }))
      (base-score u100)
    )
    (match user-data
      some-user
        (let
          (
            (referral-bonus (* (get referral-count some-user) u10))
            (activity-bonus (* tx-count u2))
            (volume-bonus (/ amount u1000))
          )
          (+ base-score referral-bonus activity-bonus volume-bonus)
        )
      base-score
    )
  )
)

;; Get today as a simple day number (stacks-block-height / 144 for ~daily)
(define-private (get-today)
  (/ burn-block-height u144)
)
