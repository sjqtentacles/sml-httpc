(* test_redirect.sml -- redirectTarget over completed responses: absolute and
   relative Location resolution for the redirect statuses, and NONE otherwise. *)

structure RedirectTests =
struct
  open Harness
  open Support

  val baseReq = {method="GET", url="http://example.com/a/b", headers=[], body=""}

  fun respWith (status, statusText, extra) =
    case Httpc.feed (newGet ())
           ("HTTP/1.1 " ^ Int.toString status ^ " " ^ statusText ^ "\r\n"
            ^ extra ^ "Content-Length: 0\r\n\r\n") of
      Httpc.Complete {response, ...} => response
    | _ => raise Fail "fixture did not complete"

  fun targetOf r = Httpc.redirectTarget {request = baseReq, response = r}

  fun optStr NONE = "NONE" | optStr (SOME s) = "SOME " ^ s

  fun run () =
    let
      val () = section "redirectTarget resolution"
      val () = checkString "302 relative Location resolved against request URL"
        ("SOME http://example.com/new", optStr (targetOf (respWith (302, "Found", "Location: /new\r\n"))))
      val () = checkString "301 absolute Location passes through"
        ("SOME https://other.example/x",
         optStr (targetOf (respWith (301, "Moved Permanently", "Location: https://other.example/x\r\n"))))
      val () = checkString "303 relative sibling resolved"
        ("SOME http://example.com/a/c", optStr (targetOf (respWith (303, "See Other", "Location: c\r\n"))))
      val () = checkString "307 resolved"
        ("SOME http://example.com/p", optStr (targetOf (respWith (307, "Temporary Redirect", "Location: /p\r\n"))))
      val () = checkString "308 resolved"
        ("SOME http://example.com/q", optStr (targetOf (respWith (308, "Permanent Redirect", "Location: /q\r\n"))))

      val () = section "redirectTarget negatives"
      val () = checkString "200 is not a redirect"
        ("NONE", optStr (targetOf (respWith (200, "OK", ""))))
      val () = checkString "302 without Location -> NONE"
        ("NONE", optStr (targetOf (respWith (302, "Found", ""))))
      val () = checkString "404 -> NONE"
        ("NONE", optStr (targetOf (respWith (404, "Not Found", "Location: /ignored\r\n"))))
    in () end
end
