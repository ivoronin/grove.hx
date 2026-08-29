(require "helix/misc.scm")
(require "helix/components.scm")
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

(provide start! focus! toggle-visible! visible? hide! show!
         space-pending? clear-space-pending!)

(define REFRESH-INTERVAL-MS 2000)

(define *model* #f)
(define *latest-frame* #f)
(define *focus-next-frame?* #f)
(define *started?* #f)
(define *theme-sources* '())
(define *grove-space-pending?* #f)

(define (space-pending?) *grove-space-pending?*)
(define (clear-space-pending!) (set! *grove-space-pending?* #f))

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
        (append arguments (list dispatch! refresh-now!)))]
    [(equal? kind 'rename)
      (apply files.prompt-rename! (append arguments (list refresh-now!)))]
    [(equal? kind 'delete)
      (apply files.confirm-delete! (append arguments (list refresh-now!)))]
    [else (error "unknown Model command")]))

(define (install-update! update-result)
  (define next-model (model.update-result-model update-result))
  (set! *model* next-model)
  (define command (model.update-result-command update-result))
  (when command
    (execute-command! command)))

(define (dispatch! transition . arguments)
  (install-update! (apply transition *model* arguments)))

(define (render-current! geometry frame)
  (if
    *focus-next-frame?*
    (let ([snapshot (observe *model* #t)])
      (set! *focus-next-frame?* #f)
      (dispatch! model.focus-frame-observed snapshot geometry))
    (dispatch! model.geometry-observed geometry))
  (define model-at-render *model*)
  (define current-layout (model.resolved-layout model-at-render))
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
    (begin
      (component.apply-clip! 0)
      (set! *latest-frame* #f)
      (input.cancel!)))
  frame)

(define (handle-event! event)
  (define was-focused? (and *model* (model.focused? *model*)))
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
    (install-update! update-result))
  (when (and was-focused?
             (input.result-pass-through? result)
             (key-event? event)
             (char? (key-event-char event))
             (char=? (key-event-char event) #\space))
    (set! *grove-space-pending?* #t))
  (input.result-pass-through? result))

(define (start-runtime! side width icons? guides?)
  (set! *model* (model.init side width icons? guides?))
  (hooks.install! dispatch!)
  (component.install! side render-current! handle-event!)
  (subscribe-to-refresh!)
  (schedule-refresh!))

(define (start! side width icons? guides? theme-sources)
  (when *started?*
    (error "Grove has already started"))
  (set! *started?* #t)
  (set! *theme-sources* theme-sources)
  (enqueue-thread-local-callback
    (lambda () (start-runtime! side width icons? guides?)))
  #t)

(define (focus!)
  (clear-space-pending!)
  (when *model*
    (set! *focus-next-frame?* #t)
    (helix.redraw))
  void)

(define (visible?) (component.visible?))
(define (hide!) (clear-space-pending!) (component.hide!))
(define (show!) (clear-space-pending!) (component.show!))
(define (toggle-visible!) (component.toggle-visible!))
