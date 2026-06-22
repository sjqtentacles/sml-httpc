(* test_decode.sml -- the incremental response decoder: Content-Length and
   chunked body reassembly (fed whole, byte-by-byte, and in odd chunks),
   keep-alive vs close, bodyless statuses, HEAD, pipelining, truncation and
   malformed input. *)

structure DecodeTests =
struct
  open Harness
  open Support

  val clResp = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Type: text/plain\r\n\r\nhello"
  val chResp = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n5\r\npedia\r\n0\r\n\r\n"

  fun run () =
    let
      val () = section "Content-Length body reassembly"
      val whole = Httpc.feed (newGet ()) clResp
      val () = checkString "whole: body" ("SOME hello", optBody whole)
      val () = check "whole: complete" (isComplete whole)
      val byByte = feedByteByByte newGet clResp
      val () = checkString "byte-by-byte: body" ("SOME hello", optBody byByte)
      val chunks3 = feedChunks newGet 3 clResp
      val () = checkString "3-byte chunks: body" ("SOME hello", optBody chunks3)
      val () = checkString "Content-Length leftover empty" ("SOME \"\"", optLeftover whole)

      val () = section "chunked body reassembly"
      val cWhole = Httpc.feed (newGet ()) chResp
      val () = checkString "chunked whole: body" ("SOME Wikipedia", optBody cWhole)
      val cByte = feedByteByByte newGet chResp
      val () = checkString "chunked byte-by-byte: body" ("SOME Wikipedia", optBody cByte)
      val cOdd = feedChunks newGet 7 chResp
      val () = checkString "chunked 7-byte chunks: body" ("SOME Wikipedia", optBody cOdd)

      val () = section "keep-alive vs close"
      val ka11 = Httpc.feed (newGet ()) "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
      val () = checkString "HTTP/1.1 default keep-alive" ("SOME true", optKa ka11)
      val close11 = Httpc.feed (newGet ()) "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
      val () = checkString "Connection: close" ("SOME false", optKa close11)
      val ka10 = Httpc.feed (newGet ()) "HTTP/1.0 200 OK\r\nContent-Length: 0\r\n\r\n"
      val () = checkString "HTTP/1.0 default close" ("SOME false", optKa ka10)
      val ka10ka = Httpc.feed (newGet ()) "HTTP/1.0 200 OK\r\nContent-Length: 0\r\nConnection: keep-alive\r\n\r\n"
      val () = checkString "HTTP/1.0 explicit keep-alive" ("SOME true", optKa ka10ka)

      val () = section "bodyless statuses + HEAD"
      val r204 = Httpc.feed (newGet ()) "HTTP/1.1 204 No Content\r\n\r\n"
      val () = checkString "204 no body" ("SOME ", optBody r204)
      val r304 = Httpc.feed (newGet ()) "HTTP/1.1 304 Not Modified\r\nContent-Length: 99\r\n\r\n"
      val () = check "304 complete despite Content-Length" (isComplete r304)
      val rHead = Httpc.feed (Httpc.newConnForMethod "HEAD")
                    "HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n"
      val () = checkString "HEAD no body despite Content-Length" ("SOME ", optBody rHead)

      val () = section "pipelining (leftover)"
      val pipe = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi"
               ^ "HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nbye"
      val p1 = Httpc.feed (newGet ()) pipe
      val () = checkString "first response body" ("SOME hi", optBody p1)
      val () = check "leftover is the second response"
        (case leftoverOf p1 of
           SOME lo => String.isPrefix "HTTP/1.1 200 OK" lo andalso String.isSubstring "bye" lo
         | NONE => false)
      (* decode the leftover with a fresh connection *)
      val p2 = case leftoverOf p1 of SOME lo => Httpc.feed (newGet ()) lo | NONE => Httpc.Failed "no leftover"
      val () = checkString "second response body" ("SOME bye", optBody p2)

      val () = section "close-delimited body via finish"
      val cdMid = Httpc.feed (newGet ()) "HTTP/1.1 200 OK\r\n\r\nstreamed-bytes"
      val () = check "no length/chunked -> NeedMore until finish" (isNeedMore cdMid)
      val cdDone = case cdMid of Httpc.NeedMore cn => Httpc.finish cn | p => p
      val () = checkString "finish completes close-delimited body" ("SOME streamed-bytes", optBody cdDone)
      val () = checkString "close-delimited is not keep-alive" ("SOME false", optKa cdDone)

      val () = section "incomplete + malformed"
      val partialHead = Httpc.feed (newGet ()) "HTTP/1.1 200 OK\r\nContent-L"
      val () = check "partial head -> NeedMore" (isNeedMore partialHead)
      val partialBody = Httpc.feed (newGet ()) "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nabc"
      val () = check "partial body -> NeedMore" (isNeedMore partialBody)
      val truncated = case partialBody of Httpc.NeedMore cn => Httpc.finish cn | p => p
      val () = check "finish on truncated body -> Failed" (isFailed truncated)
      val malformed = Httpc.feed (newGet ()) "NOT-A-STATUS-LINE\r\n\r\n"
      val () = check "malformed head -> Failed" (isFailed malformed)
    in () end

  and optBody p = (case bodyOf p of SOME b => "SOME " ^ b | NONE => "NONE")
  and optLeftover p = (case leftoverOf p of SOME b => "SOME " ^ "\"" ^ b ^ "\"" | NONE => "NONE")
  and optKa p = (case keepAliveOf p of SOME b => "SOME " ^ Bool.toString b | NONE => "NONE")
end
