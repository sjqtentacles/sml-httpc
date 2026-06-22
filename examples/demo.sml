(* sml-httpc demo: build a request's exact wire bytes, then drive the pure
   incremental decoder over a captured response delivered in awkward chunks,
   and resolve a redirect target. All inputs are fixed, so the output is fully
   deterministic and byte-identical across MLton and Poly/ML. No sockets are
   involved -- this is the pure core. *)

fun line s = print (s ^ "\n")
fun showStr s = "\"" ^ String.toString s ^ "\""

val () = line "sml-httpc demo (pure core)"
val () = line "=========================="

(* 1. Build a request. *)
val {hostport, bytes} = Httpc.buildRequest
  { method = "GET", url = "http://example.com/index.html?lang=en"
  , headers = [("Accept", "text/html"), ("User-Agent", "sml-httpc/0")]
  , body = "" }
val () = line ("connect to : " ^ hostport)
val () = line  "request bytes:"
val () = line ("  " ^ showStr bytes)

(* 2. Decode a chunked response delivered 5 bytes at a time. *)
val response =
  "HTTP/1.1 200 OK\r\n\
  \Content-Type: text/plain\r\n\
  \Transfer-Encoding: chunked\r\n\r\n\
  \6\r\nHello,\r\n7\r\n world!\r\n0\r\n\r\n"

fun drive conn i =
  if i >= String.size response then Httpc.feed conn ""
  else
    let val piece = String.substring (response, i, Int.min (5, String.size response - i))
    in case Httpc.feed conn piece of
         Httpc.NeedMore cn => drive cn (i + 5)
       | p => p
    end

val () = line ""
val () = case drive (Httpc.newConn ()) 0 of
    Httpc.Complete {response, keepAlive, ...} =>
      ( line ("status     : " ^ Int.toString (#status response) ^ " " ^ #reason response)
      ; line ("body       : " ^ showStr (#body response))
      ; line ("keep-alive : " ^ Bool.toString keepAlive) )
  | Httpc.NeedMore _ => line "decode: still need more bytes"
  | Httpc.Failed m => line ("decode failed: " ^ m)

(* 3. Resolve a redirect. *)
val redirect =
  case Httpc.feed (Httpc.newConn ())
         "HTTP/1.1 301 Moved Permanently\r\nLocation: /v2/index.html\r\nContent-Length: 0\r\n\r\n" of
    Httpc.Complete {response, ...} =>
      Httpc.redirectTarget
        { request = {method="GET", url="http://example.com/index.html", headers=[], body=""}
        , response = response }
  | _ => NONE
val () = line ""
val () = line ("redirect   : " ^ (case redirect of SOME t => t | NONE => "(none)"))
