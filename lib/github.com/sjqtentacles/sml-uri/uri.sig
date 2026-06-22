(* uri.sig

   A generic URI per RFC 3986. Components are stored *raw* (still
   percent-encoded) so that round-tripping `parse`/`toString` is exact;
   decode individual pieces with `Percent.decode` as needed.

       scheme "://" authority path [ "?" query ] [ "#" fragment ]

   Each optional component is NONE when absent (distinct from present-but-
   empty, e.g. `foo:` has scheme "foo" and empty path). *)

signature URI =
sig
  type uri =
    { scheme    : string option
    , authority : string option   (* host[:port], possibly userinfo@ *)
    , path      : string
    , query     : string option
    , fragment  : string option }

  (* Parse any URI or relative reference (RFC 3986 Appendix B regex). Total. *)
  val parse    : string -> uri
  (* Reassemble (RFC 3986 section 5.3). toString o parse is the identity. *)
  val toString : uri -> string

  (* Resolve a (possibly relative) reference against a base URI
     (RFC 3986 section 5.2). *)
  val resolve  : uri -> uri -> uri   (* resolve base ref *)
  (* Convenience over strings. *)
  val resolveStr : string -> string -> string

  (* RFC 3986 5.2.4 remove_dot_segments, exposed for reuse/testing.
     E.g. "/a/b/c/./../../g" -> "/a/b/g". *)
  val removeDotSegments : string -> string

  (* RFC 3986 section 6 syntax-based normalization: lowercase the scheme and
     host, drop the default port for the scheme (http 80, https 443, ftp 21,
     ws 80, wss 443), normalize percent-encoding (uppercase hex, decode
     unreserved), and remove_dot_segments on the path. Does not normalize the
     empty path; pass the result through `toString` to serialize. *)
  val normalize : uri -> uri

  (* RFC 3986 section 5 in reverse: produce a (relative) reference r such that
     `resolve base r` reproduces target. When base and target do not share a
     scheme and authority, or base's path is not a prefix of target's, the
     target is returned unchanged (mirrors java.net.URI.relativize). *)
  val relativize : uri -> uri -> uri   (* relativize base target *)

  (* Component setters returning a modified URI. *)
  val withPath        : uri -> string -> uri
  val withQuery       : uri -> string -> uri   (* sets query to SOME q *)
  val withFragment    : uri -> string -> uri   (* sets fragment to SOME f *)
  val withoutQuery    : uri -> uri             (* sets query to NONE *)
  val withoutFragment : uri -> uri             (* sets fragment to NONE *)

  (* Parsed query of the URI's query component (form-urlencoded). *)
  val queryParams : uri -> (string * string) list
end
