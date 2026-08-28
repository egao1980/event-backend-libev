(in-package #:event-backend-libev)

(defvar *ev-callbacks* (make-hash-table :test #'eql))

(defun %addr (ptr) (pointer-address ptr))

(defun %register (ptr kind data)
  (setf (gethash (%addr ptr) *ev-callbacks*) (cons kind data))
  ptr)

(defun %unregister (ptr)
  (remhash (%addr ptr) *ev-callbacks*))

(defun %lookup (ptr)
  (gethash (%addr ptr) *ev-callbacks*))

(defun %ensure-loop-open (loop)
  (when (libev-loop-closed-p loop)
    (error 'event-loop-error :message "event loop is closed"))
  loop)

;;; sb-ext:atomic-swap / atomic-exchange are missing on several SBCL builds;
;;; compare-and-swap is the portable primitive for cons-cell places.
(defun %steal-wake-queue (loop)
  "Atomically take and clear LOOP's wake-queue (newest-first)."
  #+sbcl
  (return-from %steal-wake-queue
    (loop for old = (slot-value loop 'wake-queue)
          when (eq (sb-ext:compare-and-swap
                    (slot-value loop 'wake-queue) old nil)
                   old)
            return old))
  (shiftf (libev-loop-wake-queue loop) nil))

(defun %push-wake-queue (loop function)
  "Atomically push FUNCTION onto LOOP's wake-queue."
  #+sbcl
  (return-from %push-wake-queue
    (loop for old = (slot-value loop 'wake-queue)
          when (eq (sb-ext:compare-and-swap
                    (slot-value loop 'wake-queue)
                    old (cons function old))
                   old)
            return function))
  (push function (libev-loop-wake-queue loop)))

(defclass libev-backend (event-backend)
  ()
  (:default-initargs :name "libev"))

(defun make-libev-backend ()
  #+windows (error 'unsupported-operation
                   :message "libev backend is Unix-only (no Windows)")
  (load-libev)
  (make-instance 'libev-backend))

(defclass libev-loop (event-loop)
  ((ptr :initarg :ptr :reader libev-loop-ptr)
   (async :initarg :async :reader libev-loop-async)
   (wake-queue :initform nil :accessor libev-loop-wake-queue)
   (closed :initform nil :accessor libev-loop-closed-p)
   (running :initform nil :accessor libev-loop-running-p)
   (closing :initform nil :accessor libev-loop-closing-p)
   (submit-pool :initform nil :accessor libev-loop-submit-pool)))

(defclass libev-handle (event-handle)
  ((ptr :initarg :ptr :reader libev-handle-ptr)
   (kind :initarg :kind :reader libev-handle-kind)))

(defun %ensure-submit-pool (loop)
  (or (libev-loop-submit-pool loop)
      (setf (libev-loop-submit-pool loop)
            (make-thread-pool
             :name (format nil "event-submit-~A"
                           (backend-name (event-loop-backend loop)))))))

(defun %shutdown-submit-pool (loop)
  (let ((pool (libev-loop-submit-pool loop)))
    (when pool
      (executor-shutdown pool :wait t)
      (setf (libev-loop-submit-pool loop) nil))))

(defcallback %ev-timer-cb :void ((loop :pointer) (w :pointer) (revents :int))
  (declare (ignore loop revents))
  (let ((entry (%lookup w)))
    (when entry
      (let* ((data (cdr entry))
             (fn (getf data :fn))
             (eh (getf data :event-handle))
             (ev-loop (getf data :loop)))
        (ev-timer-stop (libev-loop-ptr ev-loop) w)
        (unwind-protect
             (when (and fn eh (not (event-handle-canceled-p eh)))
               (funcall fn))
          (when (%lookup w)
            (%unregister w)
            (foreign-free w))
          (when eh
            (setf (event-handle-canceled-p eh) t
                  (slot-value eh 'ptr) (cffi:null-pointer))))))))

(defcallback %ev-idle-cb :void ((loop :pointer) (w :pointer) (revents :int))
  (declare (ignore loop revents))
  (let ((entry (%lookup w)))
    (when entry
      (let* ((data (cdr entry))
             (fn (getf data :fn))
             (eh (getf data :event-handle))
             (ev-loop (getf data :loop)))
        (ev-idle-stop (libev-loop-ptr ev-loop) w)
        (unwind-protect
             (when (and fn eh (not (event-handle-canceled-p eh)))
               (funcall fn))
          (when (%lookup w)
            (%unregister w)
            (foreign-free w))
          (when eh
            (setf (event-handle-canceled-p eh) t
                  (slot-value eh 'ptr) (cffi:null-pointer))))))))

(defcallback %ev-async-cb :void ((loop :pointer) (w :pointer) (revents :int))
  (declare (ignore loop revents))
  (let ((entry (%lookup w)))
    (when entry
      (let ((ev-loop (getf (cdr entry) :loop)))
        (dolist (fn (nreverse (%steal-wake-queue ev-loop)))
          (handler-case (funcall fn)
            (error (e)
              (warn "wake callback error: ~A" e))))))))

(defcallback %ev-io-cb :void ((loop :pointer) (w :pointer) (revents :int))
  (declare (ignore loop))
  (let ((entry (%lookup w)))
    (when entry
      (let* ((data (cdr entry))
             (fn (getf data :fn))
             (eh (getf data :event-handle))
             (status (if (logtest revents +ev-error+) :error :ok)))
        (when (and fn eh (not (event-handle-canceled-p eh)))
          (funcall fn status))))))

(defmethod make-event-loop ((backend libev-backend) &key)
  (load-libev)
  (let* ((loop-ptr (ev-loop-new 0))
         (async-ptr (foreign-alloc :uint8
                                   :count (foreign-type-size '(:struct ev-async)))))
    (when (null-pointer-p loop-ptr)
      (error 'event-loop-error :message "ev_loop_new failed"))
    (let ((loop (make-instance 'libev-loop
                               :backend backend
                               :ptr loop-ptr
                               :async async-ptr)))
      (%ev-async-init async-ptr (callback %ev-async-cb))
      (ev-async-start loop-ptr async-ptr)
      ;; Don't keep the loop alive solely for the wake notifier.
      (ev-unref loop-ptr)
      (%register async-ptr :async (list :loop loop))
      loop)))


(defmethod run ((backend libev-backend) (loop libev-loop) &key (stop-when-idle t))
  (%ensure-loop-open loop)
  (with-event-loop-var (loop)
    (let ((loop-ptr (libev-loop-ptr loop)))
      (setf (libev-loop-running-p loop) t)
      (unless stop-when-idle
        (ev-ref loop-ptr))
      (unwind-protect
           (ev-run loop-ptr 0)
        (setf (libev-loop-running-p loop) nil)
        (when (libev-loop-closing-p loop)
          (%finalize-close-loop loop))
        (unless stop-when-idle
          (ev-unref loop-ptr)))))
  loop)

(defmethod stop ((backend libev-backend) (loop libev-loop))
  "Stop LOOP. Safe from any thread: ev_break is only valid inside ev_run
callbacks, so off-loop calls are routed through the async wake watcher."
  (%ensure-loop-open loop)
  (if (eq loop *event-loop*)
      (ev-break (libev-loop-ptr loop) +evbreak-one+)
      (wake-call backend loop
                 (lambda ()
                   (ev-break (libev-loop-ptr loop) +evbreak-one+))))
  loop)

(defmethod defer ((backend libev-backend) (loop libev-loop) function &key)
  (%ensure-loop-open loop)
  (let* ((ptr (foreign-alloc :uint8 :count (foreign-type-size '(:struct ev-idle))))
         (eh (make-instance 'libev-handle :loop loop :ptr ptr :kind :idle)))
    (%ev-idle-init ptr (callback %ev-idle-cb))
    (%register ptr :idle (list :fn function :event-handle eh :loop loop))
    (ev-idle-start (libev-loop-ptr loop) ptr)
    eh))

(defmethod sleep* ((backend libev-backend) (loop libev-loop) seconds &key callback)
  (%ensure-loop-open loop)
  (let* ((ptr (foreign-alloc :uint8 :count (foreign-type-size '(:struct ev-timer))))
         (eh (make-instance 'libev-handle :loop loop :ptr ptr :kind :timer))
         (fn (or callback (lambda ()))))
    (%ev-timer-init ptr (callback %ev-timer-cb) seconds 0d0)
    (%register ptr :timer (list :fn fn :event-handle eh :loop loop))
    (ev-timer-start (libev-loop-ptr loop) ptr)
    eh))

(defmethod cancel ((backend libev-backend) (handle libev-handle))
  (call-next-method)
  (let ((ptr (libev-handle-ptr handle))
        (loop (event-handle-loop handle)))
    ;; Idempotent: callbacks free the watcher after fire.
    (when (and (pointerp ptr) (not (null-pointer-p ptr)) (%lookup ptr))
      (case (libev-handle-kind handle)
        (:timer (ignore-errors (ev-timer-stop (libev-loop-ptr loop) ptr)))
        (:idle (ignore-errors (ev-idle-stop (libev-loop-ptr loop) ptr)))
        (:io (ignore-errors (ev-io-stop (libev-loop-ptr loop) ptr))))
      (%unregister ptr)
      (ignore-errors (foreign-free ptr))
      (setf (slot-value handle 'ptr) (cffi:null-pointer))))
  handle)


(defun %ev-io-events (direction)
  (ecase direction
    (:none 0)
    (:read +ev-read+)
    (:write +ev-write+)
    (:read-write (logior +ev-read+ +ev-write+))))

(defmethod register-io ((backend libev-backend) (loop libev-loop) fd direction callback &key)
  (%ensure-loop-open loop)
  (when (eq direction :none)
    (error 'event-io-error
           :message "register-io DIRECTION cannot be :none (use update-io)"))
  (let* ((ptr (foreign-alloc :uint8 :count (foreign-type-size '(:struct ev-io))))
         (eh (make-instance 'libev-handle :loop loop :ptr ptr :kind :io))
         (events (%ev-io-events direction)))
    (%ev-io-init ptr (callback %ev-io-cb) fd events)
    (%register ptr :io (list :fn callback :event-handle eh :loop loop))
    (ev-io-start (libev-loop-ptr loop) ptr)
    eh))

(defmethod update-io ((backend libev-backend) (handle libev-handle) direction
                      &key (callback nil callbackp))
  "Change ev_io interest in place (stop → set events → start)."
  (unless (eq (libev-handle-kind handle) :io)
    (error 'event-io-error :message "update-io requires an io handle"
           :handle handle))
  (when (event-handle-canceled-p handle)
    (error 'event-canceled :handle handle :message "update-io on canceled handle"))
  (let* ((ptr (libev-handle-ptr handle))
         (loop (event-handle-loop handle))
         (entry (%lookup ptr))
         (events (%ev-io-events direction)))
    (unless (and (pointerp ptr) (not (null-pointer-p ptr)) entry loop)
      (error 'event-io-error :message "update-io: io handle not registered"
             :handle handle))
    (when callbackp
      (setf (getf (cdr entry) :fn) callback))
    (ev-io-stop (libev-loop-ptr loop) ptr)
    (unless (zerop events)
      (setf (foreign-slot-value ptr '(:struct ev-io) 'events)
            (logior events +ev-iofdset+))
      (ev-io-start (libev-loop-ptr loop) ptr))
    handle))

(defmethod wake ((backend libev-backend) (loop libev-loop))
  (%ensure-loop-open loop)
  (ev-async-send (libev-loop-ptr loop) (libev-loop-async loop))
  loop)

(defmethod wake-call ((backend libev-backend) (loop libev-loop) function)
  (%ensure-loop-open loop)
  (%push-wake-queue loop function)
  (wake backend loop)
  loop)

(defun %wait-loop-stopped (loop)
  (loop while (libev-loop-running-p loop)
        do #+sbcl (sb-thread:thread-yield)
           #-sbcl (sleep 0.001)))

(defun %finalize-close-loop (loop)
  (unless (libev-loop-closed-p loop)
    (let ((async (libev-loop-async loop))
          (ptr (libev-loop-ptr loop)))
      (ignore-errors (ev-async-stop ptr async))
      (%unregister async)
      (foreign-free async)
      (ev-loop-destroy ptr)
      (setf (libev-loop-closed-p loop) t
            (libev-loop-closing-p loop) nil)))
  loop)

(defun close-loop (loop)
  (%shutdown-submit-pool loop)
  (unless (libev-loop-closed-p loop)
    (when (and (libev-loop-running-p loop) (not (eq loop *event-loop*)))
      (wake-call (event-loop-backend loop) loop (lambda () (close-loop loop)))
      (%wait-loop-stopped loop)
      (loop while (not (libev-loop-closed-p loop))
            do #+sbcl (sb-thread:thread-yield)
               #-sbcl (sleep 0.001))
      (return-from close-loop loop))
    (let ((backend (event-loop-backend loop))
          (async (libev-loop-async loop))
          (ptr (libev-loop-ptr loop))
          (handles '()))
      (maphash (lambda (addr entry)
                 (declare (ignore addr))
                 (let ((data (cdr entry)))
                   (when (and (eq (getf data :loop) loop)
                              (getf data :event-handle))
                     (push (getf data :event-handle) handles))))
               *ev-callbacks*)
      (dolist (h handles)
        (cancel backend h))
      (ev-break ptr +evbreak-all+)
      (ignore-errors (ev-async-send ptr async))
      (setf (libev-loop-closing-p loop) t)
      (unless (and (libev-loop-running-p loop) (eq loop *event-loop*))
        (%wait-loop-stopped loop)
        (%finalize-close-loop loop))))
  loop)
