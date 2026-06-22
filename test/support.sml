(* support.sml -- helpers for driving the pure response decoder from fixtures:
   feed a whole buffer, feed one byte at a time, or feed in fixed-size chunks.
   These exercise the incremental state machine the way a socket would deliver
   bytes in arbitrary pieces. *)

structure Support =
struct
  (* Feed `s` to a fresh decoder one byte at a time; return the final progress.
     A NeedMore that is still pending after the last byte is returned as-is. *)
  fun feedByteByByte mk s =
    let
      fun go conn i =
        if i >= String.size s then Httpc.feed conn ""
        else
          case Httpc.feed conn (String.substring (s, i, 1)) of
            Httpc.NeedMore cn => go cn (i + 1)
          | p => p
    in go (mk ()) 0 end

  (* Feed `s` in chunks of `k` bytes. *)
  fun feedChunks mk k s =
    let
      val n = String.size s
      fun go conn i =
        if i >= n then Httpc.feed conn ""
        else
          let val sz = Int.min (k, n - i)
          in case Httpc.feed conn (String.substring (s, i, sz)) of
               Httpc.NeedMore cn => go cn (i + sz)
             | p => p
          end
    in go (mk ()) 0 end

  fun newGet () = Httpc.newConn ()

  (* Accessors that summarise a progress value into comparable pieces. *)
  fun bodyOf (Httpc.Complete {response, ...}) = SOME (#body response)
    | bodyOf _ = NONE

  fun statusOf (Httpc.Complete {response, ...}) = SOME (#status response)
    | statusOf _ = NONE

  fun leftoverOf (Httpc.Complete {leftover, ...}) = SOME leftover
    | leftoverOf _ = NONE

  fun keepAliveOf (Httpc.Complete {keepAlive, ...}) = SOME keepAlive
    | keepAliveOf _ = NONE

  fun isComplete (Httpc.Complete _) = true | isComplete _ = false
  fun isNeedMore (Httpc.NeedMore _) = true | isNeedMore _ = false
  fun isFailed   (Httpc.Failed _)   = true | isFailed _   = false
end
