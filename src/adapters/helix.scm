(require "helix/misc.scm")
(require (prefix-in helix. "helix/commands.scm"))
(require (prefix-in expansion. "../domain/expansion.scm"))
(require (prefix-in layout. "../domain/layout.scm"))
(require (prefix-in model. "../domain/model.scm"))
(require (prefix-in path. "../domain/path.scm"))
(require (prefix-in render. "helix/render.scm"))
(require (prefix-in scanner. "scanner.scm"))
(require (prefix-in git. "git.scm"))
(require (prefix-in host. "helix/host.scm"))
(require (prefix-in files. "helix/files.scm"))
(require (prefix-in hooks. "helix/hooks.scm"))
(require (prefix-in input. "helix/input.scm"))
(require (prefix-in theme. "helix/theme.scm"))
(require (prefix-in component. "helix/component.scm"))

(provide start! focus! visibility-toggle!)

(define REFRESH-INTERVAL-MS 2000)

(define *model* #f)
(define *latest-frame* #f)
(define *focus-next-frame?* #f)
(define *started?* #f)
(define *theme-sources* '())

(struct rendered-frame (root layout))

(define (observe model-at-observation scan-active-path?)
  (define observed-root (host.workspace-root))
  (define active-path (host.active-path))
  (define active-id
    (path.id-for-path observed-root active-path))
  (define base-expansion
    (if
      (equal? observed-root (model.root model-at-observation))
      (model.expansion model-at-observation)
      (expansion.empty)))
  (define scan-scope
    (if
      (and scan-active-path? active-id)
      (expansion.expand-ancestors base-expansion active-id)
      base-expansion))
  (model.observation-snapshot
    observed-root
    (scanner.scan observed-root scan-scope)
    (git.observe observed-root)
    active-id))

(define (refresh-now!)
  (define snapshot (observe *model* #f))
  (dispatch! model.observation-received snapshot))

(define (schedule-refresh!)
  (enqueue-thread-local-callback refresh-now!))

(define (created-file! root id)
  (dispatch! model.created-file-open-requested root id))

(define (subscribe-to-refresh!)
  (define (schedule-next!)
    (enqueue-thread-local-callback-with-delay
      REFRESH-INTERVAL-MS
      (lambda ()
        (refresh-now!)
        (schedule-next!))))
  (schedule-next!))

(define (execute-command! command)
  (define kind (model.model-command-kind command))
  (define arguments (model.model-command-arguments command))
  (cond
    [(equal? kind 'refresh)
      (schedule-refresh!)]
    [(equal? kind 'open-file)
      (apply
        (lambda (root id mode)
          (host.open-file! (path.path-for-id root id) mode))
        arguments)]
    [(equal? kind 'create)
      (apply
        files.prompt-create!
        (append arguments (list created-file! refresh-now!)))]
    [(equal? kind 'rename)
      (apply files.prompt-rename! (append arguments (list refresh-now!)))]
    [(equal? kind 'delete)
      (apply files.confirm-delete! (append arguments (list refresh-now!)))]
    [else (error "unknown Model command")]))

(define (release-pane!)
  (component.apply-clip! 0)
  (set! *latest-frame* #f)
  (input.cancel!))

(define (commit! update-result)
  (define was-requested? (model.presentation-requested? *model*))
  (set! *model* (model.update-result-model update-result))
  (define requested? (model.presentation-requested? *model*))
  (define presentation-changed?
    (not (equal? was-requested? requested?)))
  (when (and presentation-changed? (not requested?))
    (release-pane!))
  (define command (model.update-result-command update-result))
  (when command
    (execute-command! command))
  presentation-changed?)

(define (commit-and-redraw-if-needed! update-result)
  (when (commit! update-result)
    (helix.redraw)))

(define (dispatch! transition . arguments)
  (commit-and-redraw-if-needed!
    (apply transition *model* arguments)))

(define (render-current! geometry frame)
  (if
    *focus-next-frame?*
    (let ([snapshot (observe *model* #t)])
      (set! *focus-next-frame?* #f)
      (commit!
        (model.focus-frame-observed *model* snapshot geometry)))
    (commit! (model.geometry-observed *model* geometry)))
  (define model-at-render *model*)
  (define current-layout (model.presented-layout model-at-render))
  (if current-layout
    (begin
      (component.apply-clip! (layout.width current-layout))
      (render.draw!
        frame
        current-layout
        (model.row-facts model-at-render)
        (theme.resolve
          *theme-sources*
          (model.icons? model-at-render)
          (model.guides? model-at-render)))
      (set! *latest-frame*
        (rendered-frame (model.root model-at-render) current-layout)))
    (release-pane!))
  frame)

(define (handle-event! event)
  (define current-layout
    (and
      *latest-frame*
      (equal? (rendered-frame-root *latest-frame*) (model.root *model*))
      (rendered-frame-layout *latest-frame*)))
  (unless current-layout
    (input.cancel!))
  (define result (input.handle! *model* current-layout event))
  (define update-result (input.result-update result))
  (when update-result
    (commit-and-redraw-if-needed! update-result))
  (input.result-pass-through? result))

(define (start-runtime! side width icons? guides? visibility)
  (set! *model* (model.init side width icons? guides? visibility))
  (component.install! side render-current! handle-event!)
  (hooks.install! dispatch!)
  (subscribe-to-refresh!)
  (refresh-now!))

(define (start! side width icons? guides? visibility theme-sources)
  (when *started?*
    (error "Grove has already started"))
  (set! *started?* #t)
  (set! *theme-sources* theme-sources)
  (enqueue-thread-local-callback
    (lambda () (start-runtime! side width icons? guides? visibility)))
  #t)

(define (enqueue-after-start! action)
  (when *started?*
    (enqueue-thread-local-callback action))
  void)

(define (focus!)
  (enqueue-after-start!
    (lambda ()
      (set! *focus-next-frame?* #t)
      (helix.redraw))))

(define (visibility-toggle!)
  (enqueue-after-start!
    (lambda ()
      ; Keep this struct-to-struct conversion direct. ADR 0001 covers Steel
      ; JIT corruption.
      (commit-and-redraw-if-needed!
        (model.visibility-toggle-requested *model*)))))
