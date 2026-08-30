(require "helix/editor.scm")
(require "helix/components.scm")
(require "helix/misc.scm")
(require-builtin steel/filesystem)
(require (prefix-in helix. "helix/commands.scm"))
(require (prefix-in path. "../../domain/path.scm"))
(require (prefix-in host. "host.scm"))

(provide prompt-create! prompt-rename! confirm-delete!)

(define (observe-entry value)
  (define parent (parent-name value))
  (define name (file-name value))
  (with-handler
    (lambda (error-value) error-value)
    (let loop ([iterator (read-dir-iter parent)])
      (define entry (read-dir-iter-next! iterator))
      (cond
        [(not entry) #f]
        [(string=? name (read-dir-entry-file-name entry))
          entry]
        [else (loop iterator)]))))

(define (entry-kind observation)
  (and
    (read-dir-iter-entry? observation)
    (cond
      [(read-dir-entry-is-symlink? observation) 'link]
      [(read-dir-entry-is-dir? observation) 'directory]
      [(read-dir-entry-is-file? observation) 'file]
      [else #f])))

(define (source-error observation)
  (cond
    [(error-object? observation) (to-string observation)]
    [(not observation) "source does not exist"]
    [(not (entry-kind observation)) "source type is unsupported"]
    [else #f]))

(define (destination-error observation)
  (cond
    [(error-object? observation) (to-string observation)]
    [(read-dir-iter-entry? observation) "destination already exists"]
    [else #f]))

(define (documents-under source)
  (filter
    (lambda (document-id)
      (define candidate (editor-document->path document-id))
      (and
        candidate
        (path.id-for-path source candidate)))
    (editor-all-documents)))

(define (first-dirty documents)
  (define document (findf editor-document-dirty? documents))
  (and document (editor-document->path document)))

(define (close-affected! documents)
  (define active-path (host.active-path))
  (define (active? path) (equal? path active-path))
  (define paths (map editor-document->path documents))
  (define ordered
    (append
      (filter (lambda (path) (not (active? path))) paths)
      (filter active? paths)))
  (when (pair? ordered)
    (apply helix.buffer-close ordered)))

(define (refuse! description reason)
  (set-error!
    (string-append "Cannot " description ": " reason)))

(define (dirty-problem root documents)
  (define document (first-dirty documents))
  (and
    document
    (string-append
      (or (path.id-for-path root document) document)
      " has unsaved changes")))

(define (occupied-problem path)
  (and (pair? (documents-under path)) "destination is open in Helix"))

(define (commit! description refresh! mutate! reconcile!)
  (define error-value
    (with-handler
      (lambda (value) value)
      (begin
        (mutate!)
        #f)))
  (unless error-value
    (set-status! ""))
  (refresh!)
  (if error-value
    (refuse! description (to-string error-value))
    (reconcile!)))

(define (execute-create!
         kind
         root
         destination-id
         created-file!
         refresh!)
  (define destination (path.path-for-id root destination-id))
  (define description
    (string-append
      "create "
      (if (equal? kind 'file) "file " "directory ")
      destination-id))
  (define problem
    (or
      (occupied-problem destination)
      (destination-error (observe-entry destination))))
  (if
    problem
    (refuse! description problem)
    (commit!
      description
      refresh!
      (lambda ()
        (if
          (equal? kind 'file)
          (call-with-output-file destination (lambda (_) #t))
          (create-directory! destination)))
      (lambda ()
        (when (equal? kind 'file)
          (created-file! root destination-id))))))

(define (execute-rename! root source-id destination-id refresh!)
  (define source (path.path-for-id root source-id))
  (define destination (path.path-for-id root destination-id))
  (define description
    (string-append "rename or move " source-id " to " destination-id))
  (define documents (documents-under source))
  (define active-source? (equal? source (host.active-path)))
  (define problem
    (or
      (source-error (observe-entry source))
      (and (not active-source?) (dirty-problem root documents))
      (occupied-problem destination)
      (destination-error (observe-entry destination))))
  (cond
    [problem
      (refuse! description problem)]
    [active-source?
      (commit!
        description
        refresh!
        (lambda () (helix.move destination))
        (lambda () #t))]
    [else
      (commit!
        description
        refresh!
        (lambda ()
          (rename-file-or-directory! source destination))
        (lambda () (close-affected! documents)))]))

(define (execute-delete! root source-id refresh!)
  (define source (path.path-for-id root source-id))
  (define description (string-append "delete " source-id))
  (define source-observation (observe-entry source))
  (define documents (documents-under source))
  (define problem
    (or
      (source-error source-observation)
      (dirty-problem root documents)))
  (if
    problem
    (refuse! description problem)
    (commit!
      description
      refresh!
      (lambda ()
        (if
          (equal? (entry-kind source-observation) 'directory)
          (delete-directory! source)
          (delete-file! source)))
      (lambda () (close-affected! documents)))))

(define (prompt-create! kind root parent-id created-file! refresh!)
  (define label
    (string-append
      (if (equal? kind 'file) "New file in " "New directory in ")
      (if
        (path.root-id? parent-id)
        "./"
        (string-append parent-id "/"))))
  (push-component!
    (prompt
      label
      (lambda (input-value)
        (define destination-id
          (path.child-id parent-id input-value))
        (execute-create!
          kind
          root
          destination-id
          created-file!
          refresh!)))))

(define (prompt-rename! root source-id refresh!)
  (push-component!
    (prompt
      (string-append "Rename or move " source-id " to ")
      (lambda (destination-id)
        (execute-rename!
          root
          source-id
          destination-id
          refresh!)))))

(define (confirm-delete! root source-id recursive? refresh!)
  (define message
    (string-append
      "Permanently delete "
      source-id
      (if recursive? "/ recursively" "")
      "? y to confirm"))
  (push-component!
    (new-component!
      "grove-delete-confirmation"
      #f
      (lambda (_state rect frame)
        (define row
          (- (+ (area-y rect) (area-height rect)) 1))
        (buffer/clear-with
          frame
          (area (area-x rect) row (area-width rect) 1)
          (theme-scope-ref "ui.background"))
        (frame-set-string!
          frame
          (area-x rect)
          row
          message
          (theme-scope-ref "ui.text"))
        frame)
      (hash
        "handle_event"
        (lambda (_state event)
          (cond
            [(key-event? event)
              (define character (key-event-char event))
              (define modifier (key-event-modifier event))
              (when
                (and
                  (= modifier 0)
                  (char? character)
                  (char=? character #\y))
                (execute-delete!
                  root
                  source-id
                  refresh!))
              event-result/close]
            [(or (mouse-event? event) (paste-event? event))
              event-result/close]
            [else event-result/ignore]))
        "cursor"
        (lambda (_state _rect) #f)))))
