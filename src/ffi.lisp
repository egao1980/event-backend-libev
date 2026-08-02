(in-package #:event-backend-libev)

;;; Unix-only. Init macros from ev.h are inlined here using groveled layouts.

(defparameter +ev-read+ (foreign-enum-value 'ev-event :read))
(defparameter +ev-write+ (foreign-enum-value 'ev-event :write))
(defparameter +ev-iofdset+ (foreign-enum-value 'ev-event :iofdset))
(defparameter +ev-error+ (foreign-enum-value 'ev-event :error))
(defparameter +evrun-nowait+ (foreign-enum-value 'ev-run-flags :nowait))
(defparameter +evrun-once+ (foreign-enum-value 'ev-run-flags :once))
(defparameter +evbreak-one+ (foreign-enum-value 'ev-break-how :one))
(defparameter +evbreak-all+ (foreign-enum-value 'ev-break-how :all))

(define-foreign-library libev

  (:darwin (:or "libev.4.dylib" "libev.dylib"
                "/opt/homebrew/lib/libev.dylib"
                "/usr/local/lib/libev.dylib"))
  (:unix (:or "libev.so.4" "libev.so"))
  (t (:default "libev")))

(defun %native-search-dirs ()
  (let ((dirs '()))
    (dolist (var '("EVENT_PROTOCOL_NATIVE" "CL_STACK_LIBEV_NATIVE"))
      (let ((v (uiop:getenv var)))
        (when (and v (plusp (length v)))
          (push v dirs))))
    (ignore-errors
      (let* ((sys (asdf:find-system :event-backend-libev nil))
             (root (when sys (asdf:system-source-directory sys))))
        (when root
          (push (namestring (merge-pathnames "native/" root)) dirs)
          (push (namestring
                 (merge-pathnames
                  (format nil "lib/~A-~A/"
                          #+darwin "darwin"
                          #+linux "linux"
                          #-(or darwin linux) "unknown"
                          #+(or x86-64 x64) "amd64"
                          #+(or arm64 aarch64) "arm64"
                          #-(or x86-64 x64 arm64 aarch64) "unknown")
                  root))
                dirs))))
    (nreverse dirs)))

(defun load-libev ()
  (dolist (dir (%native-search-dirs))
    (when (and dir (uiop:directory-exists-p dir))
      (pushnew dir cffi:*foreign-library-directories* :test #'equal)))
  (unless (foreign-library-loaded-p 'libev)
    (load-foreign-library 'libev))
  t)

(defcfun ("ev_loop_new" ev-loop-new) :pointer (flags :unsigned-int))
(defcfun ("ev_loop_destroy" ev-loop-destroy) :void (loop :pointer))
(defcfun ("ev_run" ev-run) :int (loop :pointer) (flags :int))
(defcfun ("ev_break" ev-break) :void (loop :pointer) (how :int))
(defcfun ("ev_ref" ev-ref) :void (loop :pointer))
(defcfun ("ev_unref" ev-unref) :void (loop :pointer))

(defcfun ("ev_timer_start" ev-timer-start) :void (loop :pointer) (w :pointer))
(defcfun ("ev_timer_stop" ev-timer-stop) :void (loop :pointer) (w :pointer))
(defcfun ("ev_idle_start" ev-idle-start) :void (loop :pointer) (w :pointer))
(defcfun ("ev_idle_stop" ev-idle-stop) :void (loop :pointer) (w :pointer))
(defcfun ("ev_async_start" ev-async-start) :void (loop :pointer) (w :pointer))
(defcfun ("ev_async_stop" ev-async-stop) :void (loop :pointer) (w :pointer))
(defcfun ("ev_async_send" ev-async-send) :void (loop :pointer) (w :pointer))
(defcfun ("ev_io_start" ev-io-start) :void (loop :pointer) (w :pointer))
(defcfun ("ev_io_stop" ev-io-stop) :void (loop :pointer) (w :pointer))

(defun %zero-foreign (ptr size)
  (loop for i below size do (setf (mem-aref ptr :uint8 i) 0)))

(defun %ev-init-watcher (w cb)
  "ev_init: active=pending=0, priority=0, cb=CB."
  (setf (foreign-slot-value w '(:struct ev-watcher) 'active) 0
        (foreign-slot-value w '(:struct ev-watcher) 'pending) 0
        (foreign-slot-value w '(:struct ev-watcher) 'priority) 0
        (foreign-slot-value w '(:struct ev-watcher) 'data) (null-pointer)
        (foreign-slot-value w '(:struct ev-watcher) 'cb) cb))

(defun %ev-timer-init (w cb after repeat)
  (%zero-foreign w (foreign-type-size '(:struct ev-timer)))
  (%ev-init-watcher w cb)
  (setf (foreign-slot-value w '(:struct ev-timer) 'at) (float after 1.0d0)
        (foreign-slot-value w '(:struct ev-timer) 'repeat) (float repeat 1.0d0)))

(defun %ev-idle-init (w cb)
  (%zero-foreign w (foreign-type-size '(:struct ev-idle)))
  (%ev-init-watcher w cb))

(defun %ev-async-init (w cb)
  (%zero-foreign w (foreign-type-size '(:struct ev-async)))
  (%ev-init-watcher w cb))

(defun %ev-io-init (w cb fd events)
  (%zero-foreign w (foreign-type-size '(:struct ev-io)))
  (%ev-init-watcher w cb)
  (setf (foreign-slot-value w '(:struct ev-io) 'next) (null-pointer)
        (foreign-slot-value w '(:struct ev-io) 'fd) fd
        (foreign-slot-value w '(:struct ev-io) 'events)
        (logior events +ev-iofdset+)))
