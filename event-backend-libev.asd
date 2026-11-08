;;; Stub for reading this .asd before cffi-grovel is installed (#. = read-time).
#.(progn
    (unless (find-package "CFFI-GROVEL")
      (make-package "CFFI-GROVEL" :use '())
      (export (intern "GROVEL-FILE" "CFFI-GROVEL") "CFFI-GROVEL"))
    nil)

(defsystem "event-backend-libev"
  :version "0.2.1"
  :description "libev backend for event-protocol (Unix second backend; no Windows)"
  :author "egao1980"
  :license "MIT"
  :defsystem-depends-on ("cffi-grovel" "asdf-native")
  :depends-on ("cffi" "event-protocol" "cl-stack-executors")
  :serial t
  :pathname "src"
  ;; Prefer overlay grovel-cache/ (no CC). Local-dev falls back to grovel-file.
  :components
  #.(let* ((asd (or *load-truename* *load-pathname*))
           (root (when asd (uiop:pathname-directory-pathname asd)))
           (cache (when root (probe-file (merge-pathnames "grovel-cache/grovel.cffi.lisp" root)))))
      (if cache
          '((:file "package")
            ;; $EVENT_PROTOCOL_NATIVE, native/ (overlay), lib/<os>-<arch>/
            ;; (checkout), then the system libev (CFFI's search, incl. Homebrew).
            (:native-library "ev" :versions ("4") :env "EVENT_PROTOCOL_NATIVE" :system t
             :if-feature (:not :windows))
            (:file "grovel-cached" :pathname "../grovel-cache/grovel.cffi")
            (:file "ffi")
            (:file "backend")
            (:file "submit"))
          '((:file "package")
            (:native-library "ev" :versions ("4") :env "EVENT_PROTOCOL_NATIVE" :system t
             :if-feature (:not :windows))
            (cffi-grovel:grovel-file "grovel")
            (:file "ffi")
            (:file "backend")
            (:file "submit"))))
  :in-order-to ((test-op (test-op "event-backend-libev/tests")))
  ;; Native-library overlays: lib/<os>-<arch>/ per platform, derived from the
  ;; :native-library components. The grovel output folds into the same platform.
  :properties
  (:cl-repo
   (:provides ("event-backend-libev")
    :overlays
    ((:platform (:os "linux" :arch "amd64")
      :layers ((:role "cffi-grovel-output"
                :files (("grovel/linux-amd64/grovel.cffi.lisp" . "grovel.cffi.lisp")))))
     (:platform (:os "linux" :arch "arm64")
      :layers ((:role "cffi-grovel-output"
                :files (("grovel/linux-arm64/grovel.cffi.lisp" . "grovel.cffi.lisp")))))
     (:platform (:os "darwin" :arch "arm64")
      :layers ((:role "cffi-grovel-output"
                :files (("grovel/darwin-arm64/grovel.cffi.lisp" . "grovel.cffi.lisp")))))))))

(defsystem "event-backend-libev/tests"
  :depends-on ("event-backend-libev" "event-protocol/conformance" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "conformance"))
  :perform (test-op (o c)
             (unless (symbol-call :event-backend-libev/tests :run-conformance)
               (error "event-protocol/conformance failed against libev"))))
