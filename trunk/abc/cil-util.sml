structure CILUtil :> CILUTIL =
struct

  structure BC =
  struct
    (* PERF could use unique ids, hashtable, etc. *)
    type label = string
    structure SM = SplayMapFn(type ord_key = string
                              val compare = String.compare)
    type 'a blockcollector = 'a SM.map ref
    val label_ctr = ref 0
    fun genlabel s =
      let in
        label_ctr := !label_ctr + 1;
        "l$" ^ s ^ "$" ^ Int.toString (!label_ctr)
      end
    fun label s = s ^ "$"
    fun empty () = ref SM.empty
    fun insert (r : 'a blockcollector, l, v : 'a) =
      r := SM.insert(!r, l, v)
    fun extract (r : 'a blockcollector) =
      let
        val v = SM.listItemsi (!r)
      in
        r := SM.empty;
        v
      end
  end

  (* XXX there are several of these, which could collide.
     Should rationalize. *)
  val ctr = ref 0
  fun newlocal s =
    let in
      ctr := !ctr + 1;
      s ^ "$u" ^ Int.toString (!ctr)
    end

  fun genvar s =
    let in
      ctr := !ctr + 1;
      "v$" ^ s ^ "$" ^ Int.toString (!ctr)
    end

end