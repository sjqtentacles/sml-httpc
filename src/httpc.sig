(* httpc.sig

   A pure, sans-IO HTTP/1.1 *client* state machine layered on the pure
   sml-http message codec (which vendors sml-uri). It does two things, neither
   of which touches a socket, clock, or DNS:

     1. buildRequest: turn a structured request into the exact bytes to put on
        a connection, deriving the request-target and Host from the URL.

     2. an incremental response decoder: created with newConn, then fed
        received bytes with `feed`. It reports whether more bytes are needed,
        or that a complete response has been decoded (reassembling
        Content-Length or chunked bodies), along with the keep-alive decision
        and any leftover (pipelined) bytes. `finish` signals end-of-stream
        (connection closed) for close-delimited responses.

   Plus `redirectTarget`, a pure decision over a completed response that
   resolves a (possibly relative) Location against the request URL.

   Everything is byte-in/byte-out and fully fixture-testable. Actual sockets
   live in the separate, quarantined `sml-httpc-tool`, which is NOT part of the
   dual-compiler purity guarantee. *)

signature HTTPC =
sig
  type request =
    { method  : string                 (* "GET", "POST", ... *)
    , url     : string                  (* absolute URL, e.g. "http://h/p?q" *)
    , headers : (string * string) list  (* extra request headers *)
    , body    : string }

  exception Httpc of string

  (* buildRequest req -> {hostport, bytes}
     `bytes` is the exact origin-form HTTP/1.1 request to send. `hostport` is
     host:port for the connection (default port 80 for http / 443 for https).
     A Host header is added from the URL authority if the caller did not supply
     one; a Content-Length is added for a non-empty body when neither
     Content-Length nor Transfer-Encoding was supplied. Raises Httpc if the URL
     has no authority (host). *)
  val buildRequest : request -> { hostport : string, bytes : string }

  (* Opaque incremental response decoder. *)
  type conn
  val newConn : unit -> conn
  (* As newConn, but tells the decoder the request method, so a HEAD response
     (which carries no body even with a Content-Length) is framed correctly. *)
  val newConnForMethod : string -> conn

  datatype progress =
      NeedMore of conn
    | Complete of { response : Http.response, leftover : string, keepAlive : bool }
    | Failed of string

  (* Feed received bytes into the decoder. *)
  val feed : conn -> string -> progress

  (* Signal that the peer closed the connection (end of stream). Completes a
     close-delimited response (no Content-Length, not chunked); otherwise
     Failed if the message is still truncated. *)
  val finish : conn -> progress

  (* For a completed response, the absolute URL to follow on a redirect
     (3xx with a Location), resolving a relative Location against the request
     URL. NONE for non-redirects or a missing Location. *)
  val redirectTarget : { request : request, response : Http.response }
                    -> string option
end
