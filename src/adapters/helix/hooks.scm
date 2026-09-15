(require "helix/ext.scm")
(require "helix/misc.scm")
(require "helix/editor.scm")
(require (prefix-in model. "../../domain/model.scm"))
(require (prefix-in path. "../../domain/path.scm"))
(require (prefix-in host. "host.scm"))

(provide install!)

; ADR 0011: retained callbacks must not capture local helper bindings.
(define (ids-for root paths)
  (filter
    string?
    (map (lambda (value) (path.id-for-path root value)) paths)))

(define (observe-host! dispatch!)
  (define root (host.workspace-root))
  (dispatch!
    model.host-observed
    root
    (path.id-for-path root (host.active-path))))

(define (observe-unsaved! dispatch!)
  (define root (host.workspace-root))
  (dispatch! model.unsaved-observed root (ids-for root (host.unsaved-paths))))

(define (install! dispatch!)
  (define (document-focus-lost! _event)
    (observe-host! dispatch!))
  (define (document-opened! _document-id)
    (observe-unsaved! dispatch!))
  (define (document-changed! _document-id _old-text)
    (observe-unsaved! dispatch!))
  (define (document-saved! document-id)
    (define root (host.workspace-root))
    (dispatch!
      model.save-started
      root
      (path.id-for-path root (editor-document->path document-id))))
  (define (document-closed! _event)
    (observe-host! dispatch!)
    (observe-unsaved! dispatch!))
  (register-hook 'document-focus-lost document-focus-lost!)
  (register-hook 'document-opened document-opened!)
  (register-hook 'document-changed document-changed!)
  (register-hook 'document-saved document-saved!)
  (register-hook 'document-closed document-closed!)
  (observe-unsaved! dispatch!))
