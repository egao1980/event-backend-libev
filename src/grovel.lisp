;;;; Grovelled against ev.h at overlay build. Unix-only (libev has no Windows).
;;;;
;;;; Note: this file is DSL for cffi-grovel — only grovel forms (or #. that
;;;; expand to them). Plain LET/WHEN are unknown syntax.
(in-package #:event-backend-libev)

#.(let* ((ev (uiop:getenv "EVENT_PROTOCOL_EV_INCLUDE"))
         (extra (when (and ev (plusp (length ev)))
                  (list (format nil "-I~A/" (string-right-trim "/" ev))))))
    `(cc-flags ,@extra
               "-I/usr/local/include/"
               "-I/opt/homebrew/include/"
               "-I/usr/include/"))

(include "ev.h")

(cenum (ev-event)
  ((:read "EV_READ"))
  ((:write "EV_WRITE"))
  ((:iofdset "EV__IOFDSET"))
  ((:error "EV_ERROR")))

(cenum (ev-run-flags)
  ((:nowait "EVRUN_NOWAIT"))
  ((:once "EVRUN_ONCE")))

(cenum (ev-break-how)
  ((:cancel "EVBREAK_CANCEL"))
  ((:one "EVBREAK_ONE"))
  ((:all "EVBREAK_ALL")))

(cstruct ev-watcher "ev_watcher"
  (active "active" :type :int)
  (pending "pending" :type :int)
  (priority "priority" :type :int)
  (data "data" :type :pointer)
  (cb "cb" :type :pointer))

(cstruct ev-timer "ev_timer"
  (active "active" :type :int)
  (pending "pending" :type :int)
  (priority "priority" :type :int)
  (data "data" :type :pointer)
  (cb "cb" :type :pointer)
  (at "at" :type :double)
  (repeat "repeat" :type :double))

(cstruct ev-idle "ev_idle"
  (active "active" :type :int)
  (pending "pending" :type :int)
  (priority "priority" :type :int)
  (data "data" :type :pointer)
  (cb "cb" :type :pointer))

(cstruct ev-async "ev_async"
  (active "active" :type :int)
  (pending "pending" :type :int)
  (priority "priority" :type :int)
  (data "data" :type :pointer)
  (cb "cb" :type :pointer))

(cstruct ev-io "ev_io"
  (active "active" :type :int)
  (pending "pending" :type :int)
  (priority "priority" :type :int)
  (data "data" :type :pointer)
  (cb "cb" :type :pointer)
  (next "next" :type :pointer)
  (fd "fd" :type :int)
  (events "events" :type :int))
