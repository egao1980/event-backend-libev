(in-package #:event-backend-libev/tests)

(defun run-conformance ()
  "Set backend maker and run shared event-protocol/conformance suite."
  #+windows
  (handler-case
      (progn (make-libev-backend) nil)
    (unsupported-operation () t))
  #-windows
  (progn
    (setf event-protocol/conformance:*test-backend-maker*
          (lambda () (make-libev-backend)))
    (rove:run (asdf:find-system "event-protocol/conformance"))))
