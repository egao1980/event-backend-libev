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

; libev itself is loaded at ASDF load by the (:native-library "ev") component.

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
