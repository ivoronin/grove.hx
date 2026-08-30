(require (prefix-in tree. "tree.scm"))
(require (prefix-in path. "path.scm"))

(provide geometry geometry-width
  available?
  resolve
  scroll-by
  scroll-to
  reveal
  x
  y
  width
  height
  side
  pane-slots
  ordinary-capacity
  row-id-at
  slot-entry
  slot-pinned?
  rail-x
  rail-thumb-offset
  rail-resize-width
  rail-scroll-anchor
  rail-page-anchor)

(struct geometry-value (x y width height))
(struct slot (entry pinned?))
(struct layout-value
  (entries geometry side width
    anchor
    pane-slots
    ordinary-capacity
    start
    maximum-start
    total-rows))

(define geometry-x geometry-value-x)
(define geometry-y geometry-value-y)
(define geometry-width geometry-value-width)
(define geometry-height geometry-value-height)

(define width layout-value-width)
(define side layout-value-side)
(define pane-slots layout-value-pane-slots)
(define ordinary-capacity layout-value-ordinary-capacity)
(define maximum-start layout-value-maximum-start)

(define (x layout)
  (define host-geometry (layout-value-geometry layout))
  (if
    (equal? (side layout) 'right)
    (+ (geometry-x host-geometry)
      (- (geometry-width host-geometry) (width layout)))
    (geometry-x host-geometry)))

(define (y layout)
  (geometry-y (layout-value-geometry layout)))

(define (height layout)
  (geometry-height (layout-value-geometry layout)))

(define (geometry x y width height)
  (unless
    (and
      (integer? x)
      (>= x 0)
      (integer? y)
      (>= y 0)
      (integer? width)
      (>= width 0)
      (integer? height)
      (>= height 0))
    (error "invalid Host geometry"))
  (geometry-value x y width height))

(define (available? host-geometry requested-width)
  (and
    host-geometry
    (> (geometry-height host-geometry) 0)
    (>= (geometry-width host-geometry) (+ requested-width 1))))

(define (clamp value lower upper)
  (max lower (min upper value)))

; Keep slot construction and concatenation direct.
; ADR 0001 covers Steel JIT corruption.
(define (entry-slots entries pinned?)
  (let loop ([remaining entries] [result '()])
    (if
      (null? remaining)
      (reverse result)
      (loop
        (cdr remaining)
        (cons
          (slot (car remaining) pinned?)
          result)))))

(define (prepend-all prefix suffix)
  (if
    (null? prefix)
    suffix
    (cons
      (car prefix)
      (prepend-all (cdr prefix) suffix))))

(define (ancestor-entries visible-entries anchor-entry)
  (let loop ([ids (path.ancestor-ids (tree.entry-id anchor-entry))]
             [result '()])
    (if
      (null? ids)
      (reverse result)
      (let ([entry (tree.find visible-entries (car ids))])
        (loop
          (cdr ids)
          (if entry (cons entry result) result))))))

(define (ancestor-stack-size entry host-height)
  (define depth (path.depth (tree.entry-id entry)))
  (if (< depth host-height) depth 0))

(define (pinned-entries-at visible-entries index host-height)
  (define entry (try-list-ref visible-entries index))
  (if
    (> (ancestor-stack-size entry host-height) 0)
    (ancestor-entries visible-entries entry)
    '()))

(define (capacity-at visible-entries index host-height)
  (- host-height
    (length
      (pinned-entries-at visible-entries index host-height))))

(define (bottom-start-index visible-entries total host-height)
  (define initial (max 0 (- total host-height)))
  (let loop ([candidate initial]
             [remaining-entries (list-drop visible-entries initial)])
    (define pinned
      (ancestor-stack-size (car remaining-entries) host-height))
    (if
      (<= (+ pinned (- total candidate)) host-height)
      candidate
      (loop
        (+ candidate 1)
        (cdr remaining-entries)))))

(define (resolve visible-entries anchor host-geometry requested-width side-value)
  (unless
    (and
      (list? visible-entries)
      (or (not host-geometry) (geometry-value? host-geometry))
      (integer? requested-width)
      (> requested-width 0)
      (member side-value '(left right)))
    (error "invalid Layout"))
  (and
    (pair? visible-entries)
    (available? host-geometry requested-width)
    (let* ([host-height (geometry-height host-geometry)]
           [total (length visible-entries)]
           [anchor-index
             (or
               (and anchor (tree.index-of visible-entries anchor))
               0)]
           [maximum-start
             (bottom-start-index visible-entries total host-height)]
           [start-index
             (min anchor-index maximum-start)]
           [anchor-entry (try-list-ref visible-entries start-index)]
           [pinned
             (pinned-entries-at visible-entries start-index host-height)]
           [capacity (- host-height (length pinned))]
           [ordinary
             (take (list-drop visible-entries start-index) capacity)]
           [slots
             (prepend-all
               (entry-slots pinned #t)
               (entry-slots ordinary #f))])
      (layout-value
        visible-entries
        host-geometry
        side-value
        requested-width
        (tree.entry-id anchor-entry)
        slots
        capacity
        start-index
        maximum-start
        total))))

(define (entry-id-at visible-entries index)
  (tree.entry-id (try-list-ref visible-entries index)))

(define (row-id-at layout row)
  (define slot
    (try-list-ref
      (pane-slots layout)
      (- row (y layout))))
  (and
    slot
    (not (slot-pinned? slot))
    (tree.entry-id (slot-entry slot))))

(define (absolute-start layout numerator denominator)
  (quotient
    (+ (* numerator (maximum-start layout))
      (quotient denominator 2))
    denominator))

(define (scroll-by layout amount)
  (define next-start
    (clamp
      (+ (layout-value-start layout) amount)
      0
      (maximum-start layout)))
  (entry-id-at (layout-value-entries layout) next-start))

(define (scroll-to layout numerator denominator)
  (entry-id-at
    (layout-value-entries layout)
    (clamp
      (absolute-start layout numerator denominator)
      0
      (maximum-start layout))))

(define (ordinary-span? start capacity target-index)
  (and
    (>= target-index start)
    (< target-index (+ start capacity))))

(define (candidate-showing-target layout target-index initial-index)
  (define visible-entries (layout-value-entries layout))
  (define host-height (height layout))
  (define limit (maximum-start layout))
  (let loop ([candidate initial-index])
    (define start (min candidate limit))
    (cond
      [(ordinary-span?
          start
          (capacity-at visible-entries start host-height)
          target-index)
        (entry-id-at visible-entries start)]
      [(>= candidate target-index)
        (entry-id-at visible-entries target-index)]
      [else
        (loop (+ candidate 1))])))

(define (reveal layout id placement)
  (define target-index
    (tree.index-of (layout-value-entries layout) id))
  (cond
    [(not target-index)
      (layout-value-anchor layout)]
    [(ordinary-span?
        (layout-value-start layout)
        (layout-value-ordinary-capacity layout)
        target-index)
      (layout-value-anchor layout)]
    [(equal? placement 'first)
      id]
    [(< target-index (layout-value-start layout))
      id]
    [else
      (candidate-showing-target
        layout
        target-index
        (max
          0
          (+ 1
            (- target-index
              (layout-value-ordinary-capacity layout)))))]))

(define (rail-x layout)
  (if
    (equal? (layout-value-side layout) 'right)
    (x layout)
    (+ (x layout) (width layout) -1)))

(define (thumb-height layout)
  (define total (layout-value-total-rows layout))
  (define pane-height (height layout))
  (and
    (> total pane-height)
    (max
      1
      (quotient
        (* pane-height pane-height)
        total))))

(define (thumb-y layout)
  (define current-height (thumb-height layout))
  (and
    current-height
    (let* ([travel (- (height layout) current-height)]
           [limit (maximum-start layout)]
           [offset
             (if
               (or (= travel 0) (= limit 0))
               0
               (quotient (* (layout-value-start layout) travel) limit))])
      (+ (y layout) offset))))

(define (rail-thumb-offset layout row)
  (define current-y (thumb-y layout))
  (define current-height
    (thumb-height layout))
  (and
    current-y
    (>= row current-y)
    (< row (+ current-y current-height))
    (- row current-y)))

(define (rail-resize-width layout column)
  (min
    (- (geometry-width (layout-value-geometry layout)) 1)
    (if
      (equal? (layout-value-side layout) 'right)
      (-
        (+ (x layout)
          (width layout))
        column)
      (+ 1 (- column (x layout))))))

(define (rail-page-anchor layout row)
  (define current-y (thumb-y layout))
  (define current-height
    (thumb-height layout))
  (and
    current-y
    (cond
      [(< row current-y)
        (scroll-by layout (- (layout-value-ordinary-capacity layout)))]
      [(>= row (+ current-y current-height))
        (scroll-by layout (layout-value-ordinary-capacity layout))]
      [else #f])))

(define (rail-scroll-anchor layout row grab-offset)
  (define current-height
    (thumb-height layout))
  (define travel
    (and
      current-height
      (max 0 (- (height layout) current-height))))
  (and
    current-height
    travel
    (> travel 0)
    (let ([current-grab-offset
            (min grab-offset (- current-height 1))])
      (scroll-to
        layout
        (clamp
          (- (- row (y layout))
            current-grab-offset)
          0
          travel)
        travel))))
