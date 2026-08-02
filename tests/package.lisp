(defpackage #:event-backend-libev/tests
  (:use #:cl #:rove #:event-protocol #:event-backend-libev)
  (:shadowing-import-from #:event-protocol #:run))
(in-package #:event-backend-libev/tests)
