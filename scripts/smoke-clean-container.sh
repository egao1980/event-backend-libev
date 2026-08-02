#!/usr/bin/env bash
# Clean ubuntu:24.04 linux/amd64 smoke against GHCR event-backend-libev.
# Proves: native + grovel-cache load without C toolchain / libev-dev.
set -euo pipefail

VERSION="${1:-0.1.0}"
IMAGE="ghcr.io/egao1980/cl-systems/event-backend-libev:${VERSION}"
CACHE="${CACHE:-/tmp/event-backend-libev-smoke-cache}"
PKG="$CACHE/pkg/event-backend-libev-${VERSION}"
PROTO="$CACHE/event-protocol"
QL="$CACHE/quicklisp"

mkdir -p "$CACHE/pull" "$CACHE/pkg"
if [[ ! -f "$PKG/native/libev.so" && ! -f "$PKG/native/libev.so.4" ]] ||
   [[ ! -f "$PKG/grovel-cache/grovel.cffi.lisp" ]]; then
  command -v oras >/dev/null || { echo "need oras" >&2; exit 1; }
  rm -rf "$CACHE/pull"/* "$PKG"
  oras pull --platform linux/amd64 "$IMAGE" -o "$CACHE/pull/"
  for f in "$CACHE/pull"/*.tar.gz; do tar -xzf "$f" -C "$CACHE/pkg/"; done
  if [[ ! -d "$PKG" ]]; then
    found="$(find "$CACHE/pkg" -maxdepth 2 -type d -name 'event-backend-libev-*' | head -1)"
    [[ -n "$found" ]] || { echo "package dir missing after oras pull" >&2; exit 1; }
    PKG="$found"
  fi
fi

[[ -f "$PKG/grovel-cache/grovel.cffi.lisp" ]] || {
  echo "missing grovel-cache/grovel.cffi.lisp under $PKG" >&2
  find "$PKG" -maxdepth 3 -type f | head -40 >&2
  exit 1
}

if [[ ! -f "$PROTO/event-protocol.asd" ]]; then
  command -v git >/dev/null || { echo "need git to fetch event-protocol" >&2; exit 1; }
  rm -rf "$PROTO"
  git clone --depth 1 https://github.com/egao1980/event-protocol.git "$PROTO"
fi

SMOKE_LISP="$CACHE/smoke.lisp"
cat >"$SMOKE_LISP" <<'EOF'
(require :asdf) (require :uiop)
(defvar *pkg* (uiop:getenv "EVENT_BACKEND_LIBEV_ROOT"))
(defvar *proto* (uiop:getenv "EVENT_PROTOCOL_ROOT"))
(asdf:initialize-source-registry
 `(:source-registry
   (:directory ,(uiop:ensure-directory-pathname *pkg*))
   (:directory ,(uiop:ensure-directory-pathname *proto*))
   :inherit-configuration))
(ql:quickload "cffi" :silent t)
(asdf:load-system "event-protocol")
(asdf:load-system "event-backend-libev")
(let* ((make (find-symbol "MAKE-LIBEV-BACKEND" :event-backend-libev))
       (run (find-symbol "RUN" :event-protocol))
       (make-loop (find-symbol "MAKE-EVENT-LOOP" :event-protocol))
       (defer (find-symbol "DEFER" :event-protocol))
       (sleep* (find-symbol "SLEEP*" :event-protocol))
       (stop (find-symbol "STOP" :event-protocol))
       (backend (funcall make))
       (loop (funcall make-loop backend))
       (seen nil))
  (funcall defer backend loop (lambda () (setf seen :deferred)))
  (funcall sleep* backend loop 0.05
           :callback (lambda ()
                       (unless (eq seen :deferred)
                         (error "defer did not run before sleep callback"))
                       (setf seen :slept)
                       (funcall stop backend loop)))
  (funcall run backend loop :stop-when-idle t)
  (unless (eq seen :slept)
    (error "smoke failed: seen=~S" seen)))
(format t "~&SMOKE OK (libev overlay, no toolchain)~%")
(uiop:quit 0)
EOF

if [[ ! -f "$QL/setup.lisp" ]]; then
  docker run --rm --platform linux/amd64 \
    -e DEBIAN_FRONTEND=noninteractive \
    -v "$QL:/ql" \
    ubuntu:24.04 \
    bash -c 'apt-get update -qq && apt-get install -y -qq ca-certificates curl sbcl >/dev/null \
      && curl -fsSL -o /tmp/ql.lisp https://beta.quicklisp.org/quicklisp.lisp \
      && sbcl --noinform --non-interactive --load /tmp/ql.lisp \
           --eval "(quicklisp-quickstart:install :path #p\"/ql/\")" >/dev/null'
fi

docker run --rm --platform linux/amd64 \
  -e DEBIAN_FRONTEND=noninteractive \
  -e EVENT_BACKEND_LIBEV_ROOT=/opt/event-backend-libev \
  -e EVENT_PROTOCOL_ROOT=/opt/event-protocol \
  -e LD_LIBRARY_PATH=/opt/event-backend-libev/native \
  -v "$PKG:/opt/event-backend-libev:ro" \
  -v "$PROTO:/opt/event-protocol:ro" \
  -v "$QL:/ql:ro" \
  -v "$SMOKE_LISP:/opt/smoke.lisp:ro" \
  ubuntu:24.04 \
  bash -c 'apt-get update -qq && apt-get install -y -qq ca-certificates sbcl >/dev/null \
    && if dpkg -l libev-dev 2>/dev/null | grep -q ^ii; then echo FAIL:libev-dev; exit 1; fi \
    && if command -v gcc >/dev/null; then echo FAIL:gcc-present; exit 1; fi \
    && sbcl --noinform --non-interactive --load /ql/setup.lisp --load /opt/smoke.lisp'
