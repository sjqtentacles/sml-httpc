(* test_build.sml -- buildRequest: origin-form target, Host derivation, default
   ports, Content-Length insertion, and header passthrough. *)

structure BuildTests =
struct
  open Harness

  fun run () =
    let
      val () = section "buildRequest"

      val r1 = Httpc.buildRequest
        {method="GET", url="http://example.com/path?x=1", headers=[("Accept","*/*")], body=""}
      val () = checkString "GET hostport (default 80)" ("example.com:80", #hostport r1)
      val () = checkString "GET bytes (origin-form + Host)"
        ("GET /path?x=1 HTTP/1.1\r\nHost: example.com\r\nAccept: */*\r\n\r\n", #bytes r1)

      val r2 = Httpc.buildRequest
        {method="POST", url="https://api.test:8443/v1/items", headers=[], body="hello"}
      val () = checkString "POST hostport (explicit port)" ("api.test:8443", #hostport r2)
      val () = checkString "POST bytes (Host:port + Content-Length)"
        ("POST /v1/items HTTP/1.1\r\nHost: api.test:8443\r\nContent-Length: 5\r\n\r\nhello", #bytes r2)

      val () = section "buildRequest defaults + edge cases"
      val r3 = Httpc.buildRequest {method="GET", url="https://h/", headers=[], body=""}
      val () = checkString "https default port 443" ("h:443", #hostport r3)

      (* empty path -> "/" *)
      val r4 = Httpc.buildRequest {method="GET", url="http://h", headers=[], body=""}
      val () = checkString "empty path becomes /"
        ("GET / HTTP/1.1\r\nHost: h\r\n\r\n", #bytes r4)

      (* userinfo stripped from Host and hostport *)
      val r5 = Httpc.buildRequest {method="GET", url="http://user:pw@h:81/p", headers=[], body=""}
      val () = checkString "userinfo stripped from hostport" ("h:81", #hostport r5)
      val () = checkString "userinfo stripped from Host header"
        ("GET /p HTTP/1.1\r\nHost: h:81\r\n\r\n", #bytes r5)

      (* caller-supplied Host is not duplicated *)
      val r6 = Httpc.buildRequest
        {method="GET", url="http://h/p", headers=[("Host","override")], body=""}
      val () = checkString "caller Host respected"
        ("GET /p HTTP/1.1\r\nHost: override\r\n\r\n", #bytes r6)

      (* caller Content-Length not overridden, no auto CL when TE present *)
      val r7 = Httpc.buildRequest
        {method="POST", url="http://h/p", headers=[("Transfer-Encoding","chunked")], body="x"}
      val () = check "no auto Content-Length when Transfer-Encoding set"
        (not (String.isSubstring "Content-Length" (#bytes r7)))

      val () = checkRaises "no authority raises"
        (fn () => Httpc.buildRequest {method="GET", url="/relative/only", headers=[], body=""})
    in () end
end
