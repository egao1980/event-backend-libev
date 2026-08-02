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
   (closed :initform nil :accessor libev-loop-closed-p)))

(defclass libev-handle (event-handle)
  ((ptr :initarg :ptr :reader libev-handle-ptr)
   (kind :initarg :kind :reader libev-handle-kind)))

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
                  (slot-value eh 'ptr) (cffi:null-pointer)))))))

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
                  (slot-value eh 'ptr) (cffi:null-pointer)))))))

(defcallback %ev-async-cb :void ((loop :pointer) (w :pointer) (revents :int))
  (declare (ignore loop revents))
  (let ((entry (%lookup w)))
    (when entry
      (let ((ev-loop (getf (cdr entry) :loop)))
        (dolist (fn (nreverse
                     #+sbcl (sb-ext:atomic-swap nil (slot-value ev-loop 'wake-queue))
                     #-sbcl (shiftf (libev-loop-wake-queue ev-loop) nil)))
          (handler-case (funcall fn)
            (error (e)
              (warn "wake callback error: ~A" e))))))))

(defcallback %ev-io-cb :void ((loop :pointer) (w :pointer) (revents :int))
  (declare (ignore loop revents))
  (let ((entry (%lookup w)))
    (when entry
      (let* ((data (cdr entry))
             (fn (getf data :fn))
             (eh (getf data :event-handle)))
        (when (and fn eh (not (event-handle-canceled-p eh)))
          (funcall fn :ok))))))

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
      (unless stop-when-idle
        (ev-ref loop-ptr))
      (unwind-protect
           (ev-run loop-ptr 0)
        (unless stop-when-idle
          (ev-unref loop-ptr)))))
  loop)

(defmethod stop ((backend libev-backend) (loop libev-loop))
  (%ensure-loop-open loop)
  (ev-break (libev-loop-ptr loop) +evbreak-one+)
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


(defmethod register-io ((backend libev-backend) (loop libev-loop) fd direction callback &key)
  (%ensure-loop-open loop)
  (let* ((ptr (foreign-alloc :uint8 :count (foreign-type-size '(:struct ev-io))))
         (eh (make-instance 'libev-handle :loop loop :ptr ptr :kind :io))
         (events (ecase direction
                   (:read +ev-read+)
                   (:write +ev-write+)
                   (:read-write (logior +ev-read+ +ev-write+)))))
    (%ev-io-init ptr (callback %ev-io-cb) fd events)
    (%register ptr :io (list :fn callback :event-handle eh :loop loop))
    (ev-io-start (libev-loop-ptr loop) ptr)
    eh))

(defmethod wake ((backend libev-backend) (loop libev-loop))
  (%ensure-loop-open loop)
  (ev-async-send (libev-loop-ptr loop) (libev-loop-async loop))
  loop)

(defun wake-call (loop function)
  #+sbcl (sb-ext:atomic-push function (slot-value loop 'wake-queue))
  #-sbcl (push function (libev-loop-wake-queue loop))
  (wake (event-loop-backend loop) loop)
  loop)

(defun close-loop (loop)
  (unless (libev-loop-closed-p loop)
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
      (ignore-errors (ev-async-stop ptr async))
      (%unregister async)
      (foreign-free async)
      (ev-loop-destroy ptr)
      (setf (libev-loop-closed-p loop) t)))
  loop)
