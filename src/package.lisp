(defpackage #:event-backend-libev
  (:use #:cl #:cffi #:event-protocol)
  (:import-from #:cl-stack-executors
                #:make-thread-pool
                #:executor-runner
                #:executor-shutdown)
  (:export #:libev-backend
           #:make-libev-backend
           #:load-libev
           #:wake-call
           #:close-loop
           #:libev-loop
           #:libev-handle))
(in-package #:event-backend-libev)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (when (uiop:getenv "HOMEBREW_PREFIX")
    (pushnew :homebrew *features*))
  (when (uiop:getenv "EVENT_PROTOCOL_EV_INCLUDE")
    (pushnew :event-protocol-ev-include *features*)))

