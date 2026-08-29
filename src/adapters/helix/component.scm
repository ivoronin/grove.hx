(require "helix/components.scm")
(require "helix/ext.scm")
(require "helix/misc.scm")
(require "helix/editor.scm")
(require (prefix-in layout. "../../domain/layout.scm"))

(provide install! apply-clip! visible? hide! show! toggle-visible!)

(define GROVE-NAME "grove")
(define *clip-side* #f)
(define *clip-width* #f)
(define *render!* #f)
(define *handle-event!* #f)
(define *installed?* #f)

(define (apply-clip! width)
  (define effective-width (if *installed?* width 0))
  (unless (equal? effective-width *clip-width*)
    (if (equal? *clip-side* 'left)
      (set-editor-clip-left! effective-width)
      (set-editor-clip-right! effective-width))
    (set! *clip-width* effective-width)))

(define (install! side render! handle-event!)
  (set! *clip-side* side)
  (set! *clip-width* #f)
  (set! *render!* render!)
  (set! *handle-event!* handle-event!)
  (apply-clip! 0)
  (define (render-component! _state rect frame)
    (render!
      (layout.geometry
        (area-x rect)
        (area-y rect)
        (area-width rect)
        (area-height rect))
      frame))
  (define (handle-component-event! _state event)
    (if
      (handle-event! event)
      event-result/ignore
      event-result/consume))
  (push-component!
    (new-component!
      GROVE-NAME
      #f
      render-component!
      (hash
        "handle_event"
        handle-component-event!
        "cursor"
        (lambda (_state _rect) #f))))
  (set! *installed?* #t))

(define (visible?) *installed?*)

(define (hide!)
  (when *installed?*
    (pop-last-component! GROVE-NAME)
    (apply-clip! 0)
    (set! *installed?* #f)))

(define (show!)
  (unless *installed?*
    (install! *clip-side* *render!* *handle-event!*)))

(define (toggle-visible!)
  (if *installed?*
    (hide!)
    (show!)))
