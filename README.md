# sml-httpc

[![CI](https://github.com/sjqtentacles/sml-httpc/actions/workflows/ci.yml/badge.svg)](https://github.com/sjqtentacles/sml-httpc/actions/workflows/ci.yml)

A **pure, sans-IO HTTP/1.1 client state machine** in Standard ML, layered on
the pure [`sml-http`](https://github.com/sjqtentacles/sml-http) message codec
(which vendors [`sml-uri`](https://github.com/sjqtentacles/sml-uri)).

It does the protocol thinking — building request bytes, framing responses,
reassembling Content-Length and chunked bodies, deciding keep-alive vs close,
and resolving redirects — **without ever touching a socket, clock, or DNS**.
You build the exact request bytes, then feed received bytes in (in whatever
arbitrary pieces arrive); it tells you whether it needs more, or hands back a
fully-decoded response plus any leftover (pipelined) bytes. That makes the
entire client byte-in/byte-out and unit-testable against captured fixtures.

No FFI, no external dependencies, and **deterministic** — byte-identical under
both [MLton](http://mlton.org/) and [Poly/ML](https://www.polyml.org/).

> **Pure core + quarantined IO tool.** This repo is the *pure* core. Actual TCP
> sockets live in the separate companion
> [`sml-httpc-tool`](https://github.com/sjqtentacles/sml-httpc-tool), which is
> compiler-specific, impure, and explicitly **not** covered by the
> dual-compiler purity guarantee (mirrors the `sml-readline`/`sml-serve`
> precedent).

## Status

- 51 assertions, green on MLton and Poly/ML (byte-identical output).
- Vendors `sml-http` + `sml-uri` (Layout B), so the repo builds standalone.
- **Robust `Content-Length` parsing.** The decoder range-checks the
  `Content-Length` header via `IntInf`, bounded to a fixed 32-bit signed range:
  an oversized value degrades to close-delimited framing (the documented
  failure) instead of raising `Overflow`. On this toolchain MLton's `Int` is
  32-bit and Poly/ML's is 63-bit (both fixed width; only `IntInf` is arbitrary
  precision), so an unchecked parse would crash on MLton and diverge from
  Poly/ML.
- Covered behaviour:
  - **buildRequest** — origin-form request-target, `Host` derived from the URL
    authority (userinfo stripped), default ports (80/443), automatic
    `Content-Length` for a non-empty body.
  - **Response framing** fed whole, byte-by-byte, and in odd-sized chunks:
    Content-Length bodies, `Transfer-Encoding: chunked` reassembly,
    close-delimited bodies (via `finish`), bodyless statuses (204/304/1xx) and
    `HEAD` responses.
  - **keep-alive vs close** for HTTP/1.1 and HTTP/1.0 defaults and explicit
    `Connection` headers; **pipelining** (leftover bytes returned); **redirect**
    target resolution (301/302/303/307/308) with relative `Location` resolved
    against the request URL; truncated/malformed → `NeedMore`/`Failed`.

## Install

With [`smlpkg`](https://github.com/diku-dk/smlpkg):

```
smlpkg add github.com/sjqtentacles/sml-httpc
smlpkg sync
```

Include the MLB from your own (it pulls in the vendored `sml-http` + `sml-uri`):

```
local
  $(SML_LIB)/basis/basis.mlb
  lib/github.com/sjqtentacles/sml-httpc/... (via smlpkg)
in
  ...
end
```

This brings `structure Httpc` (and the vendored `Http` / `Headers` / `Uri`)
into scope.

## Quick start

```sml
(* 1. Build the exact request bytes to put on a connection. *)
val {hostport, bytes} = Httpc.buildRequest
  { method = "GET", url = "http://example.com/index.html?lang=en"
  , headers = [("Accept", "text/html")], body = "" }
(* hostport = "example.com:80"
   bytes    = "GET /index.html?lang=en HTTP/1.1\r\nHost: example.com\r\n..." *)

(* 2. Decode the response, feeding bytes as they arrive. *)
fun drive conn bytes =
  case Httpc.feed conn bytes of
    Httpc.NeedMore conn'                  => (* read more, then feed conn' *) ...
  | Httpc.Complete {response, leftover, keepAlive} => (* done *) ...
  | Httpc.Failed msg                      => (* protocol error *) ...

val start = Httpc.feed (Httpc.newConn ()) firstChunk

(* 3. Decide whether to follow a redirect. *)
val next = Httpc.redirectTarget {request = req, response = resp}
(* SOME absoluteUrl for a 3xx with Location, else NONE *)
```

## Demo

`make example` runs [`examples/demo.sml`](examples/demo.sml): it builds a
request, drives the decoder over a chunked response delivered five bytes at a
time, and resolves a redirect — all without a socket:

```
sml-httpc demo (pure core)
==========================
connect to : example.com:80
request bytes:
  "GET /index.html?lang=en HTTP/1.1\r\nHost: example.com\r\nAccept: text/html\r\nUser-Agent: sml-httpc/0\r\n\r\n"

status     : 200 OK
body       : "Hello, world!"
keep-alive : true

redirect   : http://example.com/v2/index.html
```

## API

```sml
type request =
  { method : string, url : string, headers : (string * string) list, body : string }

exception Httpc of string

val buildRequest : request -> { hostport : string, bytes : string }

type conn
val newConn          : unit -> conn
val newConnForMethod : string -> conn   (* so HEAD responses are framed right *)

datatype progress =
    NeedMore of conn
  | Complete of { response : Http.response, leftover : string, keepAlive : bool }
  | Failed of string

val feed   : conn -> string -> progress
val finish : conn -> progress            (* signal end-of-stream (peer closed) *)

val redirectTarget : { request : request, response : Http.response } -> string option
```

| Function | Behavior |
| --- | --- |
| `buildRequest req` | exact origin-form request bytes + `host:port`; adds `Host` (from the URL, userinfo stripped) and `Content-Length` (non-empty body) when absent; raises `Httpc` if the URL has no host |
| `feed conn bytes` | push received bytes into the decoder: `NeedMore` (keep reading), `Complete` (response + leftover + keep-alive), or `Failed` |
| `finish conn` | end-of-stream: completes a close-delimited body, else `Failed` if still truncated |
| `redirectTarget {request, response}` | absolute URL to follow for a 3xx with `Location` (relative resolved against the request URL), else `NONE` |

### Conventions

- **Sans-IO.** No sockets, DNS, or clock. The caller owns the connection and
  just shuttles bytes; this state machine owns the protocol.
- **Bytes as `string`.** Requests and responses are raw byte strings, matching
  `sml-http`.
- **Incremental & resumable.** `feed` accepts bytes in any chunking; a pending
  `NeedMore` carries an opaque `conn` you feed again. `Complete` returns
  `leftover` so a pipelined next response can be decoded with a fresh `conn`.
- **Close-delimited responses** (no Content-Length, not chunked) are reported
  `keepAlive = false` and require `finish` once the peer closes.

## Build & test

```
make test        # MLton
make test-poly   # Poly/ML
make all-tests   # both
make example     # build + run examples/demo.sml
make clean
```

## License

MIT — see [LICENSE](LICENSE).
