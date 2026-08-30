(require (prefix-in expansion. "../src/domain/expansion.scm"))
(require (prefix-in layout. "../src/domain/layout.scm"))
(require (prefix-in model. "../src/domain/model.scm"))
(require (prefix-in row. "../src/domain/row.scm"))
(require (prefix-in tree. "../src/domain/tree.scm"))

(define ROOT "/workspace")
(define GEOMETRY (layout.geometry 0 0 40 5))

(define (check name condition)
  (unless condition
    (error (string-append "Domain law failed: " name))))

(define (any? predicate values)
  (and
    (pair? values)
    (or
      (predicate (car values))
      (any? predicate (cdr values)))))

(define (file id)
  (tree.entry id 'file))

(define (directory id)
  (tree.entry id 'directory))

(check
  "File tree kind predicates return booleans"
  (and
    (equal? #t (tree.file-kind? 'file))
    (equal? #f (tree.file-kind? 'directory))
    (equal? #t (tree.directory-kind? 'directory-link))
    (equal? #f (tree.directory-kind? 'broken-link))
    (equal? #t (tree.expandable-kind? 'unreadable-directory))
    (equal? #f (tree.expandable-kind? 'directory-link))))

(define flat-tree
  (tree.build
    (list
      (file "item-00")
      (file "item-01")
      (file "item-02")
      (file "item-03")
      (file "item-04")
      (file "item-05")
      (file "item-06")
      (file "item-07")
      (file "item-08")
      (file "item-09")
      (file "item-10")
      (file "item-11"))))

(define flat-entries
  (expansion.visible
    (expansion.empty)
    flat-tree))

(define (resolve-flat anchor geometry)
  (layout.resolve flat-entries anchor geometry 16 'left))

(define root-id "")
(define item-02-id "item-02")

(define (slot-signature current)
  (map
    (lambda (slot)
      (list
        (tree.entry-id (layout.slot-entry slot))
        (layout.slot-pinned? slot)))
    (layout.pane-slots current)))

(define top (resolve-flat root-id GEOMETRY))

(define middle (resolve-flat item-02-id GEOMETRY))
(define down-anchor (layout.scroll-by middle 1))
(define down (resolve-flat down-anchor GEOMETRY))
(define restored
  (resolve-flat (layout.scroll-by down -1) GEOMETRY))
(check
  "one row down and up restores the middle"
  (equal? (slot-signature middle) (slot-signature restored)))

(define bottom-anchor (layout.scroll-to top 1 1))
(define bottom (resolve-flat bottom-anchor GEOMETRY))
(check
  "bottom keeps its complete Ancestor stack"
  (equal?
    (slot-signature bottom)
    (list
      (list root-id #t)
      (list "item-08" #f)
      (list "item-09" #f)
      (list "item-10" #f)
      (list "item-11" #f))))

(check
  "absolute Rail movement reaches both ends"
  (and
    (equal? root-id (layout.scroll-to middle 0 1))
    (equal? bottom-anchor (layout.scroll-to middle 1 1))))

(define missing
  (resolve-flat "missing" GEOMETRY))
(check
  "a missing anchor falls back to the Workspace root"
  (equal?
    (tree.entry-id
      (layout.slot-entry
        (car (layout.pane-slots missing))))
    root-id))

(define nested-tree
  (tree.build
    (list
      (directory "outer")
      (directory "outer/inner")
      (file "outer/inner/file-00")
      (file "outer/inner/file-01")
      (file "outer/inner/file-02")
      (file "outer/inner/file-03")
      (file "tail-00")
      (file "tail-01")
      (file "tail-02"))))

(define nested-expansion
  (expansion.expand
    (expansion.expand (expansion.empty) "outer")
    "outer/inner"))

(define nested-entries
  (expansion.visible
    nested-expansion
    nested-tree))

(define nested-target "outer/inner/file-00")

(define nested-top
  (layout.resolve nested-entries root-id GEOMETRY 16 'left))
(define nested-bottom
  (layout.resolve
    nested-entries
    (layout.scroll-to nested-top 1 1)
    GEOMETRY
    16
    'left))
(check
  "Layout maps only ordinary rows to stable IDs"
  (and
    (equal? root-id (layout.row-id-at top 0))
    (not (layout.row-id-at nested-bottom 0))))
(check
  "bottom can leave unused Pane rows after the final Visible row"
  (equal?
    (slot-signature nested-bottom)
    (list
      (list root-id #t)
      (list "tail-00" #f)
      (list "tail-01" #f)
      (list "tail-02" #f))))

(define (pinned-count height)
  (length
    (filter
      layout.slot-pinned?
      (layout.pane-slots
        (layout.resolve
          nested-entries
          nested-target
          (layout.geometry 0 0 40 height)
          16
          'left)))))

(check
  "the Ancestor stack is complete or absent"
  (let loop ([height 1])
    (or
      (> height 8)
      (and
        (member (pinned-count height) '(0 3))
        (loop (+ height 1))))))

(define initial-model
  (model.init 'left 16 #t #t 'always))

(define (updated model-value transition . arguments)
  (model.update-result-model
    (apply transition model-value arguments)))

(define nested-snapshot
  (model.observation-snapshot
    ROOT
    nested-tree
    #f
    nested-target))

(define (focus-frame model-value snapshot)
  (updated
    model-value
    model.focus-frame-observed
    snapshot
    GEOMETRY))

(define expanded-model
  (focus-frame initial-model nested-snapshot))

(define bottom-id
  (layout.scroll-to (model.resolved-layout expanded-model) 1 1))

(define bottom-model
  (updated
    (updated expanded-model model.focus-released)
    model.scroll-anchor-requested
    bottom-id))

(check
  "the focus law starts with its Active file outside Layout"
  (not
    (any?
      (lambda (slot)
        (equal?
          nested-target
          (tree.entry-id (layout.slot-entry slot))))
      (layout.pane-slots (model.resolved-layout bottom-model)))))

(define focused-model
  (focus-frame bottom-model nested-snapshot))

(define unavailable-focused-model
  (updated
    initial-model
    model.focus-frame-observed
    nested-snapshot
    (layout.geometry 0 0 16 5)))

(check
  "an unavailable Pane does not expand Active file ancestors"
  (not
    (expansion.contains?
      (model.plan-file-tree-scan
        unavailable-focused-model ROOT nested-target #f)
      "outer")))

(define focused-layout (model.resolved-layout focused-model))
(define focused-facts (model.row-facts focused-model))
(define focused-cursor-slots
  (filter
    (lambda (slot)
      (and
        (not (layout.slot-pinned? slot))
        (row.cursor? focused-facts (layout.slot-entry slot))))
    (layout.pane-slots focused-layout)))

(check
  "the focus transaction returns a Layout containing one ordinary Cursor row"
  (and
    (= 1 (length focused-cursor-slots))
    (equal?
      nested-target
      (tree.entry-id
        (layout.slot-entry (car focused-cursor-slots))))))

(define open-command
  (model.update-result-command
    (model.cursor-open-requested focused-model 'normal)))

(check
  "file activation returns one tagged Model command"
  (and
    (equal? 'open-file (model.model-command-kind open-command))
    (equal?
      (list ROOT nested-target 'normal)
      (model.model-command-arguments open-command))))

(define stale-created-result
  (model.created-file-open-requested
    focused-model
    "/another-workspace"
    "created.txt"))

(check
  "a completion from another Workspace cannot transfer control"
  (and
    (model.focused? (model.update-result-model stale-created-result))
    (not (model.update-result-command stale-created-result))))

(define (ordinary-slot? current-layout id)
  (any?
    (lambda (slot)
      (and
        (not (layout.slot-pinned? slot))
        (equal? id (tree.entry-id (layout.slot-entry slot)))))
    (layout.pane-slots current-layout)))

(define (all? predicate values)
  (or
    (null? values)
    (and
      (predicate (car values))
      (all? predicate (cdr values)))))

(define (every-reveal-is-visible? placement)
  (let height-loop ([height 1])
    (or
      (> height 8)
      (and
        (all?
          (lambda (anchor-entry)
            (define initial
              (layout.resolve
                nested-entries
                (tree.entry-id anchor-entry)
                (layout.geometry 0 0 40 height)
                16
                'left))
            (all?
              (lambda (target-entry)
                (define target-id (tree.entry-id target-entry))
                (define revealed
                  (layout.resolve
                    nested-entries
                    (layout.reveal initial target-id placement)
                    (layout.geometry 0 0 40 height)
                    16
                    'left))
                (ordinary-slot? revealed target-id))
              nested-entries))
          nested-entries)
        (height-loop (+ height 1))))))

(check
  "every revealed row is an ordinary Pane row"
  (and
    (every-reveal-is-visible? 'first)
    (every-reveal-is-visible? 'nearest)))
