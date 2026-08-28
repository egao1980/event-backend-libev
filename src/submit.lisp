(in-package #:event-backend-libev)

;;; Default hop-off runner: per-loop cl-stack-executors thread pool.

(defmethod submit ((backend libev-backend) (loop libev-loop) thunk
                   &key callback error-callback executor)
  (call-next-method backend loop thunk
                    :callback callback
                    :error-callback error-callback
                    :executor (or executor
                                  (executor-runner (%ensure-submit-pool loop)))))
