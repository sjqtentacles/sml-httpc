(* httpc.sml -- pure HTTP/1.1 client state machine over the sml-http codec. *)

structure Httpc :> HTTPC =
struct
  type request =
    { method : string, url : string, headers : (string * string) list, body : string }

  exception Httpc of string

  (* ---------------- small string helpers ---------------- *)

  fun lower s = String.map Char.toLower s

  fun trim s =
    Substring.string (Substring.dropr Char.isSpace
      (Substring.dropl Char.isSpace (Substring.full s)))

  fun findChar c s =
    let val n = String.size s
        fun go i = if i >= n then NONE
                   else if String.sub (s, i) = c then SOME i else go (i + 1)
    in go 0 end

  fun lastIndexOf c s =
    let fun go i = if i < 0 then NONE
                   else if String.sub (s, i) = c then SOME i else go (i - 1)
    in go (String.size s - 1) end

  (* index of needle in hay at or after `start`; SOME start for empty needle *)
  fun findSub needle hay start =
    let
      val nn = String.size needle
      val hn = String.size hay
      fun matchAt i =
        let fun go k = k >= nn
                       orelse (String.sub (hay, i + k) = String.sub (needle, k)
                               andalso go (k + 1))
        in go 0 end
      fun loop i = if i + nn > hn then NONE
                   else if matchAt i then SOME i else loop (i + 1)
    in if nn = 0 then SOME start else loop start end

  fun containsSub sub s = String.isSubstring sub s

  fun hexToInt s =
    let
      fun dig c = if c >= #"0" andalso c <= #"9" then SOME (Char.ord c - 48)
                  else if c >= #"a" andalso c <= #"f" then SOME (Char.ord c - 87)
                  else if c >= #"A" andalso c <= #"F" then SOME (Char.ord c - 55)
                  else NONE
      fun go (i, acc) =
        if i >= String.size s then SOME acc
        else case dig (String.sub (s, i)) of
               SOME d => go (i + 1, acc * 16 + d)
             | NONE => NONE
    in if s = "" then NONE else go (0, 0) end

  (* ---------------- request building ---------------- *)

  (* split host[:port], handling [ipv6] literals *)
  fun splitHostPort s =
    if String.size s > 0 andalso String.sub (s, 0) = #"[" then
      (case findChar #"]" s of
         SOME j =>
           let val host = String.substring (s, 0, j + 1)
               val rest = String.extract (s, j + 1, NONE)
           in if String.size rest > 0 andalso String.sub (rest, 0) = #":"
              then (host, SOME (String.extract (rest, 1, NONE)))
              else (host, NONE)
           end
       | NONE => (s, NONE))
    else
      (case lastIndexOf #":" s of
         SOME i => (String.substring (s, 0, i), SOME (String.extract (s, i + 1, NONE)))
       | NONE => (s, NONE))

  fun buildRequest {method, url, headers, body} =
    let
      val uri = Uri.parse url
      val scheme = case #scheme uri of SOME s => lower s | NONE => "http"
      val auth = case #authority uri of
                   SOME a => a
                 | NONE => raise Httpc "URL has no authority (host)"
      val hostport0 = case findChar #"@" auth of
                        SOME i => String.extract (auth, i + 1, NONE)
                      | NONE => auth
      val (host, portOpt) = splitHostPort hostport0
      val port = case portOpt of
                   SOME p => p
                 | NONE => if scheme = "https" then "443" else "80"
      val path = let val p = #path uri in if p = "" then "/" else p end
      val target = path ^ (case #query uri of SOME q => "?" ^ q | NONE => "")
      val hasHost = List.exists (fn (k, _) => lower k = "host") headers
      val hasCL   = List.exists (fn (k, _) => lower k = "content-length") headers
      val hasTE   = List.exists (fn (k, _) => lower k = "transfer-encoding") headers
      val hdrs1 = if hasHost then headers else ("Host", hostport0) :: headers
      val hdrs2 = if body <> "" andalso not hasCL andalso not hasTE
                  then hdrs1 @ [("Content-Length", Int.toString (String.size body))]
                  else hdrs1
      val req : Http.request =
        { method = method, target = target, version = "HTTP/1.1"
        , headers = Headers.fromList hdrs2, body = body }
    in
      { hostport = host ^ ":" ^ port, bytes = Http.serializeRequest req }
    end

  (* ---------------- incremental response decoder ---------------- *)

  datatype conn = Conn of { buf : string, method : string }
  fun newConnForMethod m = Conn { buf = "", method = m }
  fun newConn () = newConnForMethod "GET"

  datatype progress =
      NeedMore of conn
    | Complete of { response : Http.response, leftover : string, keepAlive : bool }
    | Failed of string

  fun statusNoBody status =
    (status >= 100 andalso status < 200) orelse status = 204 orelse status = 304

  fun isHead method = lower method = "head"

  fun withBody (r : Http.response) b : Http.response =
    { version = #version r, status = #status r, reason = #reason r
    , headers = #headers r, body = b }

  fun keepAlive (r : Http.response) =
    let
      val default = (#version r = "HTTP/1.1")
    in
      case Headers.getCombined (#headers r) "Connection" of
        SOME v =>
          let val c = lower v
          in if containsSub "close" c then false
             else if containsSub "keep-alive" c then true
             else default
          end
      | NONE => default
    end

  datatype chunkScan = ChunkNeed | ChunkBad | ChunkDone of int

  (* Scan a chunked body for completeness; ChunkDone carries the number of
     bytes consumed (the chunked region length). *)
  fun scanChunked s =
    let
      val n = String.size s
      fun crlfAt pos = pos + 1 < n
                       andalso String.sub (s, pos) = #"\r"
                       andalso String.sub (s, pos + 1) = #"\n"
      fun findCrlf pos =
        if pos + 1 >= n then NONE
        else if crlfAt pos then SOME pos
        else findCrlf (pos + 1)
      fun parseHexSize line =
        let val sizeStr = case findChar #";" line of
                            SOME j => String.substring (line, 0, j)
                          | NONE => line
        in hexToInt (trim sizeStr) end
      fun loop pos =
        case findCrlf pos of
          NONE => ChunkNeed
        | SOME crlf =>
            let val line = String.substring (s, pos, crlf - pos)
            in case parseHexSize line of
                 NONE => ChunkBad
               | SOME 0 => skipTrailers (crlf + 2)
               | SOME sz =>
                   let val dataStart = crlf + 2
                       val dataEnd = dataStart + sz
                   in if dataEnd + 2 > n then ChunkNeed
                      else if not (crlfAt dataEnd) then ChunkBad
                      else loop (dataEnd + 2)
                   end
            end
      and skipTrailers pos =
        if pos + 1 >= n then ChunkNeed
        else if crlfAt pos then ChunkDone (pos + 2)
        else (case findCrlf pos of NONE => ChunkNeed | SOME crlf => skipTrailers (crlf + 2))
    in if n = 0 then ChunkNeed else loop 0 end

  fun decode method all atEof =
    case findSub "\r\n\r\n" all 0 of
      NONE => if atEof then Failed "incomplete response head"
              else NeedMore (Conn {buf = all, method = method})
    | SOME i =>
        let
          val headEnd = i + 4
          val head = String.substring (all, 0, headEnd)
          val rest = String.extract (all, headEnd, NONE)
        in
          case Http.parseResponse head of
            NONE => Failed "malformed response head"
          | SOME resp =>
              let
                val hdrs = #headers resp
                val isChunked =
                  (case Headers.getCombined hdrs "Transfer-Encoding" of
                     SOME v => containsSub "chunked" (lower v)
                   | NONE => false)
                val clOpt =
                  (case Headers.get hdrs "Content-Length" of
                     SOME v => Int.fromString (trim v)
                   | NONE => NONE)
                val noBody = isHead method orelse statusNoBody (#status resp)
                val ka = keepAlive resp
                fun completeKa k b leftover =
                  Complete {response = withBody resp b, leftover = leftover, keepAlive = k}
                fun complete b leftover = completeKa ka b leftover
                fun more () = NeedMore (Conn {buf = all, method = method})
              in
                if noBody then complete "" rest
                else if isChunked then
                  (case scanChunked rest of
                     ChunkNeed => if atEof then Failed "truncated chunked body" else more ()
                   | ChunkBad => Failed "malformed chunked body"
                   | ChunkDone consumed =>
                       let val region = String.substring (rest, 0, consumed)
                           val leftover = String.extract (rest, consumed, NONE)
                       in case Http.decodeChunked region of
                            SOME b => complete b leftover
                          | NONE => Failed "chunked decode failed"
                       end)
                else
                  (case clOpt of
                     SOME nlen =>
                       if String.size rest >= nlen
                       then complete (String.substring (rest, 0, nlen))
                                     (String.extract (rest, nlen, NONE))
                       else if atEof then Failed "truncated body" else more ()
                   | NONE =>
                       (* close-delimited: body runs to end of stream, which
                          means the peer must close, so the connection is not
                          reusable regardless of any Connection header. *)
                       if atEof then completeKa false rest "" else more ())
              end
        end

  fun feed (Conn {buf, method}) bytes = decode method (buf ^ bytes) false
  fun finish (Conn {buf, method}) = decode method buf true

  (* ---------------- redirects ---------------- *)

  fun redirectTarget {request : request, response : Http.response} =
    let val s = #status response in
      if s = 301 orelse s = 302 orelse s = 303 orelse s = 307 orelse s = 308 then
        (case Headers.get (#headers response) "Location" of
           SOME loc => SOME (Uri.resolveStr (#url request) (trim loc))
         | NONE => NONE)
      else NONE
    end
end
