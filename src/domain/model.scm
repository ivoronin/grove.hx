(require (prefix-in layout. "layout.scm"))
(require (prefix-in expansion. "expansion.scm"))
(require (prefix-in path. "path.scm"))
(require (prefix-in tree. "tree.scm"))
(require (prefix-in row. "row.scm"))

(provide init
  root
  resolved-layout
  presented-layout
  presentation-requested?
  row-facts
  icons?
  guides?
  focused?
  expansion
  observation-snapshot
  host-observed
  focus-frame-observed
  observation-received
  unsaved-observed
  save-started
  geometry-observed
  focus-released
  created-file-open-requested
  visibility-toggle-requested
  cursor-move-requested
  cursor-expansion-requested
  cursor-open-requested
  cursor-mutation-requested
  row-pressed
  scroll-anchor-requested
  resize-by-requested
  resize-to-requested
  update-result-model
  update-result-command
  model-command-kind
  model-command-arguments)

(struct model-value
  (root tree git-status unsaved-ids active-id
    expansion
    cursor
    anchor
    geometry
    width
    side
    icons?
    guides?
    visibility))

(struct observation-snapshot (root tree git-status active-id))

(struct model-command (kind arguments))
(struct update-result (model command))

(define (command kind . arguments)
  (model-command kind arguments))

(define root model-value-root)
(define icons? model-value-icons?)
(define guides? model-value-guides?)
(define expansion model-value-expansion)
(define (focused? model)
  (and (model-value-cursor model) #t))

(define MIN-WIDTH 16)
(define MAX-WIDTH 64)

(define (valid-root? value)
  (and
    (string? value)
    (> (string-length value) 0)
    (char=? (string-ref value 0) #\/)))

(define (copy-model model
         #:root
         [root-value (model-value-root model)]
         #:tree
         [file-tree (model-value-tree model)]
         #:git
         [git-status (model-value-git-status model)]
         #:unsaved
         [unsaved-ids (model-value-unsaved-ids model)]
         #:active
         [active-id (model-value-active-id model)]
         #:expansion
         [expansion-value (model-value-expansion model)]
         #:cursor
         [cursor-value (model-value-cursor model)]
         #:anchor
         [anchor-value (model-value-anchor model)]
         #:geometry
         [geometry-value (model-value-geometry model)]
         #:width
         [width-value (model-value-width model)]
         #:visibility
         [visibility-value (model-value-visibility model)])
  (model-value
    root-value
    file-tree
    git-status
    unsaved-ids
    active-id
    expansion-value
    cursor-value
    anchor-value
    geometry-value
    width-value
    (model-value-side model)
    (model-value-icons? model)
    (model-value-guides? model)
    visibility-value))

(define (without-focus model)
  (copy-model model #:cursor #f))

(define (visible-entries model)
  (if
    (and (model-value-root model) (model-value-tree model))
    (expansion.visible
      (model-value-expansion model)
      (model-value-tree model))
    '()))

(define (row-facts model)
  (row.facts
    (model-value-root model)
    (model-value-git-status model)
    (model-value-unsaved-ids model)
    (model-value-active-id model)
    (model-value-cursor model)
    (model-value-expansion model)))

(define (resolved-layout-for model entries)
  (layout.resolve
    entries
    (model-value-anchor model)
    (model-value-geometry model)
    (model-value-width model)
    (model-value-side model)))

(define (resolved-layout model)
  (resolved-layout-for model (visible-entries model)))

(define (presentation-requested? model)
  (or
    (equal? (model-value-visibility model) 'always)
    (focused? model)))

(define (presented-layout model)
  (and
    (presentation-requested? model)
    (resolved-layout model)))

(define (request-refresh model)
  (update-result model (command 'refresh)))

(define (init side-value width-value icons-value guides-value visibility-value)
  (model-value
    #f
    #f
    #f
    '()
    #f
    (expansion.empty)
    #f
    #f
    #f
    width-value
    side-value
    icons-value
    guides-value
    visibility-value))

(define (first-surviving-id entries new-ids)
  (define found
    (findf
      (lambda (entry)
        (member (tree.entry-id entry) new-ids))
      entries))
  (and found (tree.entry-id found)))

(define (reconciled-id old-entries new-entries id)
  (define old-index (and id (tree.index-of old-entries id)))
  (define new-ids (map tree.entry-id new-entries))
  (and
    old-index
    (or
      (first-surviving-id
        (list-drop old-entries (+ old-index 1))
        new-ids)
      (first-surviving-id
        (reverse (take old-entries old-index))
        new-ids))))

(define (reconciled-anchor old-model new-entries)
  (define old-anchor (model-value-anchor old-model))
  (cond
    [(and old-anchor (tree.find new-entries old-anchor))
      old-anchor]
    [else
      (define old-entries (visible-entries old-model))
      (or
        (reconciled-id old-entries new-entries old-anchor)
        path.root-id)]))

(define (install-observation-snapshot model snapshot)
  (define root-value (observation-snapshot-root snapshot))
  (unless (valid-root? root-value)
    (error "invalid Workspace root"))
  (define changed-root?
    (not (equal? root-value (model-value-root model))))
  (define file-tree (observation-snapshot-tree snapshot))
  (define base
    (copy-model
      model
      #:root
      root-value
      #:tree
      file-tree
      #:git
      (observation-snapshot-git-status snapshot)
      #:active
      (observation-snapshot-active-id snapshot)
      #:unsaved
      (if changed-root? '() (model-value-unsaved-ids model))
      #:expansion
      (if
        changed-root?
        (expansion.empty)
        (expansion.prune (model-value-expansion model) file-tree))
      #:cursor
      (if changed-root? #f (model-value-cursor model))))
  (define base-entries (visible-entries base))
  (define next-cursor
    (and
      (model-value-cursor base)
      (if
        (tree.find base-entries (model-value-cursor base))
        (model-value-cursor base)
        path.root-id)))
  (copy-model
    base
    #:cursor
    next-cursor
    #:anchor
    (if
      changed-root?
      path.root-id
      (reconciled-anchor model base-entries))))

(define (activatable-active-id model)
  (define active-id (model-value-active-id model))
  (define entry
    (and
      active-id
      (model-value-tree model)
      (tree.find (model-value-tree model) active-id)))
  (and
    entry
    (tree.file-kind? (tree.entry-kind entry))
    active-id))

(define (focus-model model)
  (define active-id (activatable-active-id model))
  (define focused-expansion
    (if
      active-id
      (expansion.expand-ancestors
        (model-value-expansion model)
        active-id)
      (model-value-expansion model)))
  (define expanded-model
    (copy-model model #:expansion focused-expansion))
  (define focused-layout (resolved-layout expanded-model))
  (if
    (not focused-layout)
    (without-focus model)
    (let* ([target-id (or active-id path.root-id)]
           [next-anchor
             (layout.reveal focused-layout target-id 'first)])
      (copy-model
        expanded-model
        #:cursor
        target-id
        #:anchor
        next-anchor))))

(define (host-observed model root-value active-id)
  (unless (valid-root? root-value)
    (error "invalid Workspace root"))
  (cond
    [(not (equal? root-value (model-value-root model)))
      (request-refresh model)]
    [(equal? active-id (model-value-active-id model))
      (update-result model #f)]
    [else
      (update-result (copy-model model #:active active-id) #f)]))

(define (unsaved-observed model root-value ids)
  (if
    (or
      (not (equal? root-value (model-value-root model)))
      (equal? ids (model-value-unsaved-ids model)))
    (update-result model #f)
    (update-result (copy-model model #:unsaved ids) #f)))

(define (save-started model root-value id)
  (if
    (not (equal? root-value (model-value-root model)))
    (update-result model #f)
    (request-refresh
      (copy-model
        model
        #:unsaved
        (filter
          (lambda (candidate) (not (equal? candidate id)))
          (model-value-unsaved-ids model))))))

(define (install-geometry model geometry-value)
  (if
    (equal? geometry-value (model-value-geometry model))
    model
    (let ([next-model
            (copy-model model #:geometry geometry-value)])
      (if
        (or
          (not (model-value-cursor next-model))
          (layout.available?
            (model-value-geometry next-model)
            (model-value-width next-model)))
        next-model
        (without-focus next-model)))))

(define (clamp value lower upper)
  (max lower (min upper value)))

(define (cursor-target entries cursor delta)
  (define current-index
    (and cursor (tree.index-of entries cursor)))
  (and
    current-index
    (try-list-ref
      entries
      (clamp
        (+ current-index delta)
        0
        (max 0 (- (length entries) 1))))))

(define (cursor-move-requested model direction)
  (define entries (visible-entries model))
  (define current-layout (resolved-layout-for model entries))
  (if
    (not current-layout)
    (update-result model #f)
    (let* ([delta
             (cond
               [(equal? direction 'previous) -1]
               [(equal? direction 'next) 1]
               [(equal? direction 'previous-page)
                 (- (layout.ordinary-capacity current-layout))]
               [(equal? direction 'next-page)
                 (layout.ordinary-capacity current-layout)]
               [else (error "invalid Cursor movement")])]
           [target
             (cursor-target
               entries
               (model-value-cursor model)
               delta)])
      (if
        (not target)
        (update-result model #f)
        (let ([target-id (tree.entry-id target)])
          (update-result
            (copy-model
              model
              #:cursor
              target-id
              #:anchor
              (layout.reveal current-layout target-id 'nearest))
            #f))))))

(define (reveal-cursor model)
  (define current-layout (resolved-layout model))
  (if
    (and current-layout (model-value-cursor model))
    (copy-model
      model
      #:anchor
      (layout.reveal
        current-layout
        (model-value-cursor model)
        'nearest))
    model))

(define (entry-for-id model id)
  (and
    id
    (model-value-tree model)
    (tree.find (model-value-tree model) id)))

(define (collapse-directory model entry)
  (define directory-id (tree.entry-id entry))
  (define (id-after-collapse stored-id)
    (if
      (and stored-id (path.id-inside? directory-id stored-id))
      directory-id
      stored-id))
  (update-result
    (copy-model
      model
      #:expansion
      (expansion.collapse-subtree
        (model-value-expansion model)
        directory-id)
      #:cursor
      (id-after-collapse (model-value-cursor model))
      #:anchor
      (id-after-collapse (model-value-anchor model)))
    #f))

(define (expand-directory model entry)
  (define directory-id (tree.entry-id entry))
  (if
    (expansion.contains?
      (model-value-expansion model)
      directory-id)
    (update-result model #f)
    (request-refresh
      (copy-model
        model
        #:expansion
        (expansion.expand
          (model-value-expansion model)
          directory-id)))))

(define (toggle-directory model entry)
  (if
    (expansion.contains?
      (model-value-expansion model)
      (tree.entry-id entry))
    (collapse-directory model entry)
    (expand-directory model entry)))

(define (request-file-open model id mode)
  (update-result
    (without-focus model)
    (command 'open-file (model-value-root model) id mode)))

(define (activate-entry model entry mode)
  (cond
    [(not entry)
      (update-result model #f)]
    [(tree.expandable? entry)
      (toggle-directory model entry)]
    [(tree.file-kind? (tree.entry-kind entry))
      (request-file-open model (tree.entry-id entry) mode)]
    [else
      (update-result model #f)]))

(define (cursor-entry model)
  (entry-for-id model (model-value-cursor model)))

; Cursor keys reveal the Cursor first, even when they then refuse to act.
(define (cursor-expansion-requested model action)
  (define revealed (reveal-cursor model))
  (define entry (cursor-entry revealed))
  (cond
    [(not (and entry (tree.expandable? entry)))
      (update-result revealed #f)]
    [(equal? action 'expand) (expand-directory revealed entry)]
    [(equal? action 'collapse) (collapse-directory revealed entry)]
    [else (error "invalid Cursor expansion action")]))

(define (cursor-open-requested model mode)
  (define revealed (reveal-cursor model))
  (activate-entry revealed (cursor-entry revealed) mode))

(define (mutation-parent-id entry)
  (define source-id (tree.entry-id entry))
  (if
    (or
      (path.root-id? source-id)
      (tree.expandable-kind? (tree.entry-kind entry)))
    source-id
    (path.parent-id source-id)))

(define (cursor-mutation-requested model action)
  (define revealed (reveal-cursor model))
  (define entry (cursor-entry revealed))
  (define source-id (and entry (tree.entry-id entry)))
  (define root-value (model-value-root revealed))
  ; The Workspace root is the one row that cannot be renamed or deleted.
  (define (outside-root command-value)
    (and (not (path.root-id? source-id)) command-value))
  (update-result
    revealed
    (cond
      [(not entry) #f]
      [(member action '(file directory))
        (command 'create action root-value (mutation-parent-id entry))]
      [(equal? action 'rename)
        (outside-root (command 'rename root-value source-id))]
      [(equal? action 'delete)
        (outside-root
          (command
            'delete
            root-value
            source-id
            (tree.expandable-kind? (tree.entry-kind entry))))]
      [else (error "invalid Cursor mutation action")])))

(define (resize-to-requested model requested-width)
  (define current-geometry (model-value-geometry model))
  (define host-limit
    (and
      current-geometry
      (- (layout.geometry-width current-geometry) 1)))
  (define upper
    (if
      host-limit
      (min MAX-WIDTH (max MIN-WIDTH host-limit))
      MAX-WIDTH))
  (define next-width (clamp requested-width MIN-WIDTH upper))
  (if
    (= next-width (model-value-width model))
    (update-result model #f)
    (update-result (copy-model model #:width next-width) #f)))

(define (focus-frame-observed model snapshot geometry-value)
  (update-result
    (focus-model
      (install-geometry
        (install-observation-snapshot model snapshot)
        geometry-value))
    #f))

(define (observation-received model snapshot)
  (update-result (install-observation-snapshot model snapshot) #f))

(define (geometry-observed model geometry-value)
  (update-result (install-geometry model geometry-value) #f))

(define (focus-released model)
  (update-result (without-focus model) #f))

(define (created-file-open-requested model root-value id)
  (if
    (equal? root-value (model-value-root model))
    (request-file-open model id 'normal)
    (update-result model #f)))

(define (visibility-toggle-requested model)
  (update-result
    (copy-model
      model
      #:visibility
      (if
        (equal? (model-value-visibility model) 'always)
        'focused
        'always))
    #f))

(define (row-pressed model id)
  (activate-entry model (entry-for-id model id) 'normal))

(define (scroll-anchor-requested model id)
  (update-result (copy-model model #:anchor id) #f))

(define (resize-by-requested model amount)
  (resize-to-requested model (+ (model-value-width model) amount)))
