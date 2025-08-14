;; InfoTrust: Decentralized Knowledge Bounty Protocol
;; A trustless ecosystem enabling knowledge seekers to post inquiry bounties with cryptographic rewards,
;; empowering wisdom providers to contribute solutions and earn STX tokens through merit-based selection.
;; Features autonomous escrow, impartial arbitration, and community-driven intellectual exchange.

;; PROTOCOL ERROR CONSTANTS

(define-constant ERR-STEWARD-EXCLUSIVE-ACTION (err u100))
(define-constant ERR-INQUIRY-BOUNTY-NONEXISTENT (err u101))
(define-constant ERR-FORBIDDEN-ACCESS-ATTEMPT (err u102))
(define-constant ERR-INADEQUATE-BOUNTY-VALUE (err u103))
(define-constant ERR-BOUNTY-LIFECYCLE-TERMINATED (err u104))
(define-constant ERR-BOUNTY-TEMPORAL-EXPIRY (err u105))
(define-constant ERR-REDUNDANT-WISDOM-SUBMISSION (err u106))
(define-constant ERR-TREASURY-INSUFFICIENCY (err u107))
(define-constant ERR-MALFORMED-PARAMETERS (err u108))
(define-constant ERR-BOUNTY-CONTAINS-PENDING-WISDOM (err u109))
(define-constant ERR-WISDOM-SUBMISSIONS-ABSENT (err u110))
(define-constant ERR-WISDOM-ENTRY-INEXISTENT (err u111))

;; PROTOCOL CONFIGURATION CONSTANTS

(define-constant protocol-steward tx-sender)
(define-constant maximum-inquiry-subject-length u128)
(define-constant maximum-inquiry-narrative-length u512)
(define-constant maximum-wisdom-payload-length u1024)
(define-constant maximum-seeker-bounty-threshold u100)
(define-constant maximum-provider-wisdom-threshold u100)
(define-constant default-protocol-treasury-rate u250) ;; 2.5% in basis points
(define-constant minimum-bounty-quantum u1000000) ;; 1 STX
(define-constant maximum-bounty-temporal-span u4320) ;; 30 days (144 blocks/day)
(define-constant basis-points-divisor u10000)

;; PROTOCOL STATE VARIABLES

(define-data-var inquiry-bounty-sequence uint u0)
(define-data-var protocol-treasury-rate uint default-protocol-treasury-rate)
(define-data-var minimum-bounty-quantum-threshold uint minimum-bounty-quantum)
(define-data-var maximum-temporal-boundary uint maximum-bounty-temporal-span)

;; PROTOCOL DATA ARCHITECTURES

;; Primary inquiry bounty registry
(define-map inquiry-bounty-ledger
    uint
    {
        bounty-originator: principal,
        inquiry-subject: (string-ascii 128),
        inquiry-narrative: (string-utf8 512),
        bounty-treasury: uint,
        temporal-expiration-height: uint,
        lifecycle-phase: (string-ascii 16),
        chosen-wisdom-curator: (optional principal),
        bounty-genesis-height: uint
    }
)

;; Wisdom contributions registry per bounty
(define-map wisdom-contribution-ledger
    {inquiry-bounty-id: uint, wisdom-curator: principal}
    {
        wisdom-payload: (string-utf8 1024),
        contribution-genesis-height: uint,
        is-elected-wisdom: bool
    }
)

;; Bounty wisdom contribution metrics
(define-map bounty-wisdom-tallies
    uint
    uint
)

;; Knowledge seeker bounty chronicles
(define-map seeker-bounty-chronicles
    principal
    (list 100 uint)
)

;; Wisdom curator contribution chronicles
(define-map curator-wisdom-chronicles
    principal
    (list 100 {bounty-id: uint, contribution-timestamp: uint})
)

;; PROTOCOL QUERY INTERFACES

(define-read-only (retrieve-bounty-manifest (bounty-id uint))
    (map-get? inquiry-bounty-ledger bounty-id)
)

(define-read-only (retrieve-wisdom-artifact (bounty-id uint) (curator principal))
    (map-get? wisdom-contribution-ledger {inquiry-bounty-id: bounty-id, wisdom-curator: curator})
)

(define-read-only (retrieve-bounty-wisdom-tally (bounty-id uint))
    (default-to u0 (map-get? bounty-wisdom-tallies bounty-id))
)

(define-read-only (retrieve-seeker-bounty-portfolio (seeker-address principal))
    (default-to (list) (map-get? seeker-bounty-chronicles seeker-address))
)

(define-read-only (retrieve-curator-wisdom-portfolio (curator-address principal))
    (default-to (list) (map-get? curator-wisdom-chronicles curator-address))
)

(define-read-only (retrieve-protocol-treasury-rate)
    (var-get protocol-treasury-rate)
)

(define-read-only (retrieve-minimum-bounty-quantum)
    (var-get minimum-bounty-quantum-threshold)
)

(define-read-only (retrieve-protocol-bounty-sequence)
    (var-get inquiry-bounty-sequence)
)

(define-read-only (verify-bounty-vitality (bounty-id uint))
    (match (map-get? inquiry-bounty-ledger bounty-id)
        bounty-manifest
        (and 
            (is-eq (get lifecycle-phase bounty-manifest) "active")
            (< block-height (get temporal-expiration-height bounty-manifest))
        )
        false
    )
)

(define-read-only (calculate-protocol-treasury-allocation (bounty-amount uint))
    (/ (* bounty-amount (var-get protocol-treasury-rate)) basis-points-divisor)
)

(define-read-only (calculate-wisdom-curator-disbursement (bounty-amount uint))
    (- bounty-amount (calculate-protocol-treasury-allocation bounty-amount))
)

;; INTERNAL PROTOCOL UTILITIES

(define-private (chronicle-seeker-bounty-creation (seeker-address principal) (bounty-id uint))
    (let 
        (
            (existing-seeker-portfolio (retrieve-seeker-bounty-portfolio seeker-address))
            (enhanced-portfolio (unwrap! (as-max-len? (append existing-seeker-portfolio bounty-id) u100) 
                (err u999)))
        )
        (map-set seeker-bounty-chronicles seeker-address enhanced-portfolio)
        (ok true)
    )
)

(define-private (chronicle-curator-wisdom-contribution (curator-address principal) (bounty-id uint))
    (let 
        (
            (existing-curator-chronicles (retrieve-curator-wisdom-portfolio curator-address))
            (new-wisdom-chronicle {bounty-id: bounty-id, contribution-timestamp: block-height})
            (enhanced-chronicles (unwrap! (as-max-len? (append existing-curator-chronicles new-wisdom-chronicle) u100) 
                (err u999)))
        )
        (map-set curator-wisdom-chronicles curator-address enhanced-chronicles)
        (ok true)
    )
)

(define-private (transition-bounty-lifecycle 
    (bounty-id uint) 
    (new-lifecycle-phase (string-ascii 16)) 
    (elected-curator-address (optional principal))
)
    (match (map-get? inquiry-bounty-ledger bounty-id)
        existing-bounty-manifest
        (begin
            (map-set inquiry-bounty-ledger bounty-id 
                (merge existing-bounty-manifest {
                    lifecycle-phase: new-lifecycle-phase, 
                    chosen-wisdom-curator: elected-curator-address
                })
            )
            (ok true)
        )
        (err u999)
    )
)

(define-private (validate-principal-authenticity (address principal))
    (not (is-eq address 'SP000000000000000000002Q6VF78))
)

(define-private (validate-quantum-positivity (amount uint))
    (> amount u0)
)

(define-private (validate-utf8-narrative-constraints (input-narrative (string-utf8 1024)) (max-length uint))
    (and (> (len input-narrative) u0) (<= (len input-narrative) max-length))
)

(define-private (validate-ascii-subject-constraints (input-subject (string-ascii 128)) (max-length uint))
    (and (> (len input-subject) u0) (<= (len input-subject) max-length))
)

;; CORE PROTOCOL OPERATIONS

(define-public (initiate-inquiry-bounty
    (inquiry-subject (string-ascii 128))
    (inquiry-narrative (string-utf8 512))
    (bounty-quantum uint)
    (temporal-duration-blocks uint)
)
    (let 
        (
            (new-bounty-id (+ (var-get inquiry-bounty-sequence) u1))
            (bounty-expiration-height (+ block-height temporal-duration-blocks))
        )
        ;; Protocol parameter validation
        (asserts! (validate-ascii-subject-constraints inquiry-subject u128) ERR-MALFORMED-PARAMETERS)
        (asserts! (validate-utf8-narrative-constraints inquiry-narrative u512) ERR-MALFORMED-PARAMETERS)
        (asserts! (>= bounty-quantum (var-get minimum-bounty-quantum-threshold)) ERR-INADEQUATE-BOUNTY-VALUE)
        (asserts! (and (> temporal-duration-blocks u0) (<= temporal-duration-blocks (var-get maximum-temporal-boundary))) ERR-MALFORMED-PARAMETERS)
        
        ;; Cryptographic escrow to protocol treasury
        (try! (stx-transfer? bounty-quantum tx-sender (as-contract tx-sender)))
        
        ;; Register inquiry bounty in protocol ledger
        (map-set inquiry-bounty-ledger new-bounty-id {
            bounty-originator: tx-sender,
            inquiry-subject: inquiry-subject,
            inquiry-narrative: inquiry-narrative,
            bounty-treasury: bounty-quantum,
            temporal-expiration-height: bounty-expiration-height,
            lifecycle-phase: "active",
            chosen-wisdom-curator: none,
            bounty-genesis-height: block-height
        })
        
        ;; Initialize wisdom contribution metrics
        (map-set bounty-wisdom-tallies new-bounty-id u0)
        
        ;; Chronicle seeker's bounty creation
        (try! (chronicle-seeker-bounty-creation tx-sender new-bounty-id))
        
        ;; Advance protocol sequence counter
        (var-set inquiry-bounty-sequence new-bounty-id)
        
        (ok new-bounty-id)
    )
)

(define-public (contribute-wisdom-solution 
    (bounty-id uint) 
    (wisdom-payload (string-utf8 1024))
)
    (let 
        (
            (bounty-manifest (unwrap! (map-get? inquiry-bounty-ledger bounty-id) ERR-INQUIRY-BOUNTY-NONEXISTENT))
            (wisdom-identifier {inquiry-bounty-id: bounty-id, wisdom-curator: tx-sender})
        )
        ;; Verify bounty vitality and temporal validity
        (asserts! (verify-bounty-vitality bounty-id) ERR-BOUNTY-LIFECYCLE-TERMINATED)
        
        ;; Validate wisdom payload constraints
        (asserts! (validate-utf8-narrative-constraints wisdom-payload u1024) ERR-MALFORMED-PARAMETERS)
        
        ;; Prevent redundant wisdom contributions
        (asserts! (is-none (map-get? wisdom-contribution-ledger wisdom-identifier)) ERR-REDUNDANT-WISDOM-SUBMISSION)
        
        ;; Archive wisdom contribution
        (map-set wisdom-contribution-ledger wisdom-identifier {
            wisdom-payload: wisdom-payload,
            contribution-genesis-height: block-height,
            is-elected-wisdom: false
        })
        
        ;; Increment bounty wisdom tally
        (map-set bounty-wisdom-tallies bounty-id 
            (+ (retrieve-bounty-wisdom-tally bounty-id) u1)
        )
        
        ;; Chronicle curator's wisdom contribution
        (try! (chronicle-curator-wisdom-contribution tx-sender bounty-id))
        
        (ok true)
    )
)

(define-public (elect-optimal-wisdom 
    (bounty-id uint) 
    (elected-wisdom-curator principal)
)
    (let 
        (
            (bounty-manifest (unwrap! (map-get? inquiry-bounty-ledger bounty-id) ERR-INQUIRY-BOUNTY-NONEXISTENT))
            (wisdom-identifier {inquiry-bounty-id: bounty-id, wisdom-curator: elected-wisdom-curator})
            (wisdom-artifact (unwrap! (map-get? wisdom-contribution-ledger wisdom-identifier) ERR-WISDOM-ENTRY-INEXISTENT))
            (total-bounty-treasury (get bounty-treasury bounty-manifest))
            (protocol-treasury-allocation (calculate-protocol-treasury-allocation total-bounty-treasury))
            (curator-disbursement (calculate-wisdom-curator-disbursement total-bounty-treasury))
        )
        ;; Verify bounty originator authority
        (asserts! (is-eq tx-sender (get bounty-originator bounty-manifest)) ERR-FORBIDDEN-ACCESS-ATTEMPT)
        
        ;; Ensure bounty remains in active lifecycle
        (asserts! (is-eq (get lifecycle-phase bounty-manifest) "active") ERR-BOUNTY-LIFECYCLE-TERMINATED)
        
        ;; Validate elected curator authenticity
        (asserts! (validate-principal-authenticity elected-wisdom-curator) ERR-MALFORMED-PARAMETERS)
        
        ;; Designate elected wisdom as optimal
        (map-set wisdom-contribution-ledger wisdom-identifier 
            (merge wisdom-artifact {is-elected-wisdom: true})
        )
        
        ;; Transition bounty to completion phase
        (try! (transition-bounty-lifecycle bounty-id "completed" (some elected-wisdom-curator)))
        
        ;; Disburse cryptographic rewards to wisdom curator
        (try! (as-contract (stx-transfer? curator-disbursement tx-sender elected-wisdom-curator)))
        
        ;; Allocate protocol treasury commission
        (try! (as-contract (stx-transfer? protocol-treasury-allocation tx-sender protocol-steward)))
        
        (ok true)
    )
)

(define-public (nullify-inquiry-bounty (bounty-id uint))
    (let 
        (
            (bounty-manifest (unwrap! (map-get? inquiry-bounty-ledger bounty-id) ERR-INQUIRY-BOUNTY-NONEXISTENT))
            (escrowed-treasury (get bounty-treasury bounty-manifest))
            (current-wisdom-tally (retrieve-bounty-wisdom-tally bounty-id))
        )
        ;; Verify bounty originator authority
        (asserts! (is-eq tx-sender (get bounty-originator bounty-manifest)) ERR-FORBIDDEN-ACCESS-ATTEMPT)
        
        ;; Ensure bounty remains active
        (asserts! (is-eq (get lifecycle-phase bounty-manifest) "active") ERR-BOUNTY-LIFECYCLE-TERMINATED)
        
        ;; Prevent nullification with pending wisdom
        (asserts! (is-eq current-wisdom-tally u0) ERR-BOUNTY-CONTAINS-PENDING-WISDOM)
        
        ;; Transition bounty to nullified state
        (try! (transition-bounty-lifecycle bounty-id "nullified" none))
        
        ;; Restitute escrowed treasury to originator
        (try! (as-contract (stx-transfer? escrowed-treasury tx-sender (get bounty-originator bounty-manifest))))
        
        (ok true)
    )
)

(define-public (process-temporal-expiry (bounty-id uint))
    (let 
        (
            (bounty-manifest (unwrap! (map-get? inquiry-bounty-ledger bounty-id) ERR-INQUIRY-BOUNTY-NONEXISTENT))
            (escrowed-treasury (get bounty-treasury bounty-manifest))
        )
        ;; Validate bounty existence and temporal expiry
        (asserts! (is-eq (get lifecycle-phase bounty-manifest) "active") ERR-BOUNTY-LIFECYCLE-TERMINATED)
        (asserts! (>= block-height (get temporal-expiration-height bounty-manifest)) ERR-BOUNTY-CONTAINS-PENDING-WISDOM)
        
        ;; Transition bounty to expired phase
        (try! (transition-bounty-lifecycle bounty-id "expired" none))
        
        ;; Restitute escrowed treasury to originator
        (try! (as-contract (stx-transfer? escrowed-treasury tx-sender (get bounty-originator bounty-manifest))))
        
        (ok true)
    )
)

;; PROTOCOL STEWARDSHIP OPERATIONS

(define-public (calibrate-protocol-treasury-rate (new-treasury-rate uint))
    (begin
        (asserts! (is-eq tx-sender protocol-steward) ERR-STEWARD-EXCLUSIVE-ACTION)
        (asserts! (<= new-treasury-rate u1000) ERR-MALFORMED-PARAMETERS) ;; Maximum 10%
        (var-set protocol-treasury-rate new-treasury-rate)
        (ok true)
    )
)

(define-public (calibrate-minimum-bounty-quantum (new-minimum-quantum uint))
    (begin
        (asserts! (is-eq tx-sender protocol-steward) ERR-STEWARD-EXCLUSIVE-ACTION)
        (asserts! (> new-minimum-quantum u0) ERR-MALFORMED-PARAMETERS)
        (var-set minimum-bounty-quantum-threshold new-minimum-quantum)
        (ok true)
    )
)

(define-public (calibrate-maximum-temporal-boundary (new-temporal-maximum uint))
    (begin
        (asserts! (is-eq tx-sender protocol-steward) ERR-STEWARD-EXCLUSIVE-ACTION)
        (asserts! (> new-temporal-maximum u0) ERR-MALFORMED-PARAMETERS)
        (var-set maximum-temporal-boundary new-temporal-maximum)
        (ok true)
    )
)

;; EMERGENCY PROTOCOL OPERATIONS

(define-public (emergency-treasury-extraction (extraction-quantum uint))
    (begin
        (asserts! (is-eq tx-sender protocol-steward) ERR-STEWARD-EXCLUSIVE-ACTION)
        (asserts! (validate-quantum-positivity extraction-quantum) ERR-MALFORMED-PARAMETERS)
        (try! (as-contract (stx-transfer? extraction-quantum tx-sender protocol-steward)))
        (ok true)
    )
)