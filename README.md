# event-backend-libev

MIT. **libev** backend for [`event-protocol`](https://github.com/egao1980/event-protocol) — Unix second backend (Woo-adjacent). **No Windows** (libev limitation).

| | |
|--|--|
| Protocol | `egao1980/event-protocol` |
| Default / Windows | [`event-backend-libuv`](https://github.com/egao1980/event-backend-libuv) |
| Matrix | linux/amd64+arm64, darwin/arm64 |

## Load / test

```bash
export HOMEBREW_PREFIX=/opt/homebrew
ros -e '(asdf:load-asd "event-backend-libev.asd")' \
    -e '(asdf:test-system "event-backend-libev")' -q
```

## Overlay

```bash
./scripts/build-libev.sh
./scripts/stage-grovel.sh event-backend-libev
```

Publish: Actions → **Publish OCI Package** (Unix matrix). Clean-container smoke:

```bash
./scripts/smoke-clean-container.sh 0.1.0
```

Tracking: [cl-stack#17](https://github.com/egao1980/cl-stack/issues/17).
