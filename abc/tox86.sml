(* And at long last, conversion to x86.

   If we had the full range of x86 opcodes, conversion from
   the ASM language to x86 would be pretty straightforward.
   There are a few big issues working against us:

    - The only jump construct we have is the family of relative short
      jumps, like JNZ, with a fixed offset. This offset is a single
      byte. Since it's printable, we can only jump from 0x20 (+32
      bytes) to 0x7e (+126 bytes). Note that there is no backward
      jump!

    - Our program needs to have backward jumps in order to perform
      loops. The only way I could even figure out to make the
      instruction pointer decrease is to overflow it. Unfortunately it
      doesn't simply work to let execution run past CS:FFFF, but it
      does work to perform a short forward jump (like the onese we
      have access to) that crosses CS:FFFF. These appear to be
      performed in on the 16-bit word, and thus wrap around to
      CS:0000.

    - All this really lets us do is get back to the beginning of the
      segment, with very little control other than that. In order to
      actually get us to an arbitrary label, we need to perform a
      series of jumps. Since the maximum displacement of any jump is
      126 bytes, we create a "ladder" of connected jumps throughout
      the code segment. Long jumps are performed by getting on this
      ladder and jumping until the desired destination is reached.
      Since the ladder "wraps around," it's possible to get anywhere.

    - The ladder is inefficient to travel along, and takes space, so
      we want it to be small. Each rung looks like this:

         rung_n:
           DEC si                     48
           JNZ rung_n+1               75 xx
         code-block:

      The register si holds the number of rungs left to traverse; when
      it reaches 0 then we enter the code block. This register can be
      16 bit, because of course there cannot be more than 64k rungs in
      the 64k code segment.

    - Note that the ladder above uses relative addressing, but all of the
      jumps in ASM are absolute! We could also do an absolute version:

          CMP_IMM AX, 0x3055          66 3d 55 30
          JNE next                    75 xx

      which isn't so bad, but is 6 bytes vs 3, requires us to use AX
      for the address (maybe fine).

      We can of course compute a relative address from an absolute one,
      because we know what address (block) we're currently at. So if
      we're currently in block src,

      JumpCond cc dst

      is

      rel = dst - src + 1 (mod the total number of blocks;
                           this can't be negative)
      si <- rel
      jmp next_rung

      (Note that a rung does DEC first, so if you want to execute that
       block, the register should be 1 when you enter the rung. This
       usually means just adding one to the register before starting.)

      and PopJumpInd is
      pop si
      sub si, src
      inc si
      jmp next_rung

      .. the belief is that this overhead (once per jump) is worth the
      increase in speed on the ladder (once per rung). Note that most
      jumps are through JumpCond, because only function pointers and
      return addresses need the complexity of PopJumpInd. (Though this
      optimization is not yet implemented.)

    - Using the ladder to jump like this does trash SI, (but can we
      make use of the fact that it is 0 upon normal entry to a block?)
      and also messes up flags. ASM doesn't need these to be preserved
      across jumps, so nor should our translation to x86.

    - Complication: Jumps can only go 126 bytes.

      A block could easily be longer than 126 bytes when assembled.
      This is not a big problem on its own; once we reach 126 bytes
      during assembly, we could insert the rung, and the too-big block
      could either jump over it or just hop onto the ladder and
      immediately off it.
         - Jumping over the rung is probably bad, because the minimum
           printable jump is 32 bytes.
         - Entering the ladder at least requires us to set the
           register correctly so that we immediately exit (probably
           means setting it to 1).
         - However, this means that if we're in the middle of
           something, we may have messed up our state. And we can't
           easily do something like push/pop, unless we can guarantee
           that nobody else will try to exit on this rung (might be
           true?).

      A reasonably simple way to deal with this is to just try
      translating a block, and if it's longer than the maximum, split
      it into two blocks (the first ending with a non-conditional jump
      to the second), and then try again. Our layout strategy will
      be based a greedy optimistic-try-then-split approach.

    - Complication: Even encoding literals takes an unpredictable
      amount of space, so splitting a block can in some cases make the
      block longer! We could bound this, but also, in the limit, we
      just need to ensure that no ASM instruction exceeds the maximum
      size for a block on its own (plus overhead). That should be easy
      to ensure.

    - Complication: Jumps must go at least 32 bytes. This means that
      we will need to pad some blocks so that the ladder can jump over
      them.

      Worse, a jump near the end of a block (and by their nature, most
      blocks have jumps near the end) must not be *too close* to the
      ladder that follows, because we must jump at leat 32 bytes. If
      we get too close, we probably should just continue *into* the
      ladder. At that point, only non-conditional jumps will work,
      unless we can manage to conditionally move a destination address
      into the reg or something fancy like that. It may occasionally
      be possible to conditionally jump to the *next* rung, if the
      next block is short enough.

    - Between the minimum and maximum sizes, there's some tradeoff,
      because we can fit more small blocks (and depending on how we
      exit them, we don't want to be executing padding...), but any
      backwards jump needs to go all the way to the end of the segment
      and so having more rungs to touch on the way is worse.

    - One additional constraint is that the program needs to start
      at some printable (actual) address, because that address needs
      to be specified in the header.

    - Note that we can pretty easily insert rungs that DON'T decrement
      SI, like they could just non-conditionally jump. We could use
      this to fill out the code segment and get to the end so that we
      can overflow. It is still usually better to stretch out the
      existing ladder, because fewer jumps to get around is faster.

    - Optimization: It could be possible to interleave some blocks, or
      have rungs that skip. This seems a bit more complexity than it
      works, but could improve code density.
    - Optimization: Some jumps will just be in range?
    - Optimization: Block layout order?
    - Optimization: Branching is pretty expensive. Computing a
      destination block with a jump table or something (for if..else)
      may be a better strategy in many cases.
*)

structure ToX86 :> TOX86 =
struct
  infixr 9 `
  fun a ` b = a b

  exception ToX86 of string

  structure A = ASM
  structure M = Machine

  val INIT_SP = Word16.fromInt 0x7e7e

  val ASSEMBLY_CTX = X86.CTX { default_32 = false }
  val RUNG_SIZE = EncodeX86.encoded_size ASSEMBLY_CTX (X86.DEC X86.SI) +
    EncodeX86.encoded_size ASSEMBLY_CTX (X86.JNZ 0w0)

  (* Actual start position of temporary frame. Note that BP will always point
     32 bytes before the frame. *)
  val TMP_FRAME_START = Word16.fromInt 0x7e80

  open X86
  infix <- <~

  open Acc
  infix // ?? ++ --

    (* bad idea?
  datatype problem =
    (* The block with the given label was bigger than the maximum
       block size. This includes the case that there was a conditional
       jump too close to the end of the block. *)
    BlockTooBig of string
  | NotEnoughBlocks
    *)

  structure SM = SplayMapFn(type ord_key = string
                            val compare = String.compare)

  fun getlabelnum labelnum label =
    case SM.find (labelnum, label) of
      NONE => raise ToX86 ("bug: label " ^ label ^ " not in map?")
    | SOME i => i

  (* Do layout of a specific block, returning the x86 bytes and
     some metadata.

     A block's code is position-indepenent, and even moreso can be
     moved relative to the next rung as long as we can modify the
     jumps to the rung. All jumps are a JCC opcode (70-7E) followed
     by a printable displacement (20-7E), so we can modify the
     displacement after the fact without changing the layout. (Note
     however that changing the order or number of blocks does change
     layout in general, because we load absolute and relative block
     numbers, and the loading of these numbers is not constant size.

     So, when we produce code for a block, we record the positions
     where we want a "jump to the next rung" displacement, and can
     move around the blocks a little bit after the fact. There's
     always at least one of these, for the rung at the head of the
     block. *)
  fun layout_block { labelnum : int SM.map,
                     num_labels : int,
                     frame_stack_start : int,
                     is_initial : bool,
                     block = A.Block { name = current_lab,
                                       tmp_frame = A.Explicit tmp_frame_size,
                                       cmds : A.explicit_cmd list } } =
    let
      (* Rewrite displacements for next rail, as discussed above.
         Byte offset from the beginning of the block. *)
      val next_jumps : int list ref = ref nil

      fun offset (A.E { offset = off, ... }) = off

      datatype cmdres =
        (* Control flow cannot reach after the last instruction
           of the accumulator, for example after translating Exit
           or a non-conditional jump. *)
          Finished of Acc.acc
        | Continue of Acc.acc

      (* XXX hoist? *)
      fun onecmd acc cmd : cmdres =
        let
          fun assert16 (t as A.E { offset, size, comment }) =
            if size = A.S16
            then ()
            else raise ToX86 ("Command requires 16-bit temporary; got " ^
                              A.explicit_tmptos t ^ " in cmd:\n" ^
                              A.explicit_cmdtos cmd)
        in
          case cmd of
            A.Label _ => raise ToX86 "bug: unexpected Label"
          | A.Init =>
              let in
                (* Sanity check... *)
                if is_initial then ()
                else raise ToX86 "bug: init instruction outside initial block?";
                (* We actually point both EBP and EBX 32 bytes before the
                   temporary and local frames, respectively. This is because
                   the smallest printable disp8 we can actually represent
                   is 0x20 = 32.

                   Whenever we access these through [EBP+disp8] (etc.), we have
                   to be careful about the difference between a tmp frame
                   offset (starts at 0) and actual displacement (starts
                   at 0x20). *)
                Continue `
                Tactics.initialize (acc,
                                    Word16.-(TMP_FRAME_START,
                                             Word16.fromInt 0x20),
                                    Word16.fromInt (frame_stack_start - 0x20))
              end
          | A.Exit => Finished `Tactics.exit acc
          | A.SaveTemps (A.Explicit n) =>
              (* Add n to EBP. We know that it's in 0x00000000-0x0000FFFF,
                 so we just modify the 16-bit part, BP. *)
              Continue `
              Tactics.add_bp acc tmp_frame_size (Word16.fromInt n)
          | A.RestoreTemps (A.Explicit n) =>
              Continue `
              Tactics.sub_bp acc tmp_frame_size (Word16.fromInt n)
          | A.ExpandFrame n =>
              Continue `
              Tactics.add_bx acc tmp_frame_size (Word16.fromInt n)
          | A.ShrinkFrame n =>
              Continue `
              Tactics.sub_bx acc tmp_frame_size (Word16.fromInt n)

          | A.Push tmp =>
              let in
                assert16 tmp;
                Continue `
                Tactics.push_tmp16 acc (offset tmp)
              end
          | A.Pop tmp =>
              let in
                assert16 tmp;
                Continue `
                Tactics.pop_tmp16 acc (offset tmp)
              end

          | A.Immediate16 (tmp, w16) =>
              let in
                assert16 tmp;
                Continue `
                Tactics.imm_tmp16 acc (offset tmp) w16
              end
          | A.LoadLabel (tmp, other_lab) =>
              let
                val idx = getlabelnum labelnum other_lab
              in
                assert16 tmp;
                Continue `
                Tactics.imm_tmp16 acc (offset tmp) (Word16.fromInt idx)
              end

          | A.PopJumpInd =>
              (* Pop the 16-bit label off the stack.
                 Compute a relative offset to that; put in SI.
                 Jump to next rung. *)
              let
                val current_idx = getlabelnum labelnum current_lab
                (* If we jump to the next rung with a value of 1, we DEC and
                   then SI will be 0. So, putting aside the modulus, we're
                   looking for exactly the distance dest_idx - current_idx. *)

                (* We'd like to compute (dest_idx - current_idx % num_labels)
                   with some caveats: A jump of 0 actually needs to be
                   represented as num_labels, not 0, because we're going to
                   start on the next rung (which would already be past the
                   current block). Worse, computing mod num_labels is way
                   too complicated without access to instructions like IDIV.

                   (Note: If we knew the number of labels was a power of two,
                   we could do this with AND_AX_IMM.)

                   Instead, we just compute (dest - current) naively, and
                   then add num_labels. This means that we *always* do at
                   least a full trip around (combination safe style!), but
                   that's probably cheaper than trying to calculate the
                   modulus in the first place, and much less code. *)

                (* Goal is to set SI = (stack_top - current_idx) + num_labels,
                   which is the same as
                   stack_top - (current_idx - num_labels)

                   So we generate
                   tmp <- immediate (current_idx - num_labels)
                   POP SI
                   SUB SI <- tmp
                   JMP to next rail *)
                val tmp = tmp_frame_size
                val subtractand = Word16.-(Word16.fromInt current_idx,
                                           Word16.fromInt num_labels)
                val () = Acc.assert_unclaimed acc SI
                val acc = acc ++ SI // POP SI ?? forget_reg16 M.ESI
                val acc = Tactics.imm_tmp16 acc tmp subtractand
                val acc = acc // SUB (S16, DH_SI <- Tactics.EBP_TEMPORARY tmp)
                (* We know that the quantity has to be positive, by
                   construction; The smallest (dest - cur) can be is
                   0 - (num_labels - 1) = 1 - num_labels, and since we add
                   num_labels, we'd get 1. So we know the processor flags
                   reflect a non-zero result. We can therefore accomplish
                   a non-conditional jump here with JNZ (or others).

                   (Note that sometimes we want to just NOP into the rung...
                   we might want to record that this is unconditional, then?) *)
                val acc = acc // JNZ 0w0
                (* And record that we need to update the displacement. *)
                val () = next_jumps := (Acc.insbytes acc - 1) :: !next_jumps
              in
                (* Don't relinquish SI, though moot since this is the end
                   of the block. *)
                Finished `
                acc
              end

          | A.Xor (a, b) =>
              let in
                (* XXX allow 8/32 *)
                assert16 a; assert16 b;
                Continue `
                Tactics.xor_tmp16 acc (offset a) (offset b)
              end

          | A.Sub (a, b) =>
              let in
                (* XXX allow 8/32 *)
                assert16 a; assert16 b;
                Continue `
                Tactics.sub_tmp16 acc (offset a) (offset b)
              end

          | A.Mov (a, b) =>
              let in
                (* XXX allow 8/32 *)
                assert16 a; assert16 b;
                Continue `
                Tactics.mov_tmp16_to_tmp16 acc (offset a) (offset b)
              end

          | A.FrameOffset (tmp, off) =>
              let
                val () = assert16 tmp
                (* We just want tmp <- ebx + off + 0x20.
                   (Addresses point to the actual object, whereas
                   ebx is offset 0x20 for efficiency.)
                   Since we sub, compute the literal as the
                   negation of off + 0x20 *)
                val subtractand =
                  Word16.~ (Word16.+ (off, Word16.fromInt 0x20))

                (* First we'll set tmp = ebx,
                   then SUB the appropriate literal. *)
                val acc = Tactics.mov16ind8 acc
                  (Tactics.EBP_TEMPORARY (offset tmp) <~ B)
              in
                Continue `
                Tactics.sub_tmp16_lit acc (offset tmp) subtractand
              end

          | A.Putc tmp =>
              let in
                (* XXX allow 8-bit? *)
                assert16 tmp;
                Continue `
                Tactics.putc16 acc (offset tmp)
              end

          (*
          | A.Load8 (dst, addr) =>
          | A.Load16 (dst, addr) =>
          | A.Store8 (addr, src) =>
          | A.Store16 (addr, src) =>
          | A.JumpCond (cond, lab) =>
          | A.Immediate8 (tmp, w8) =>
          | A.Immediate32 (tmp, w32) =>
          | A.Add (a, b) =>
          | A.Complement a =>
            *)
          | _ =>
              let in
                (* print ("Unimplemented cmd: " ^
                   ASM.explicit_cmdtos cmd ^ "\n"); *)
                Continue `
                (acc // MESSAGE ("TODO " ^ ASM.explicit_cmdtos cmd))
                (* raise ToX86 ("Unimplemented cmd: " ^
                   ASM.explicit_cmdtos cmd) *)
              end
        end

      val acc =
        if is_initial
        then
          (* If we're just starting, we know nothing. *)
          Acc.empty ASSEMBLY_CTX M.all_unknown
        else
          (* For a normal block, we know that EBX and EBP are claimed
             for frame pointers and shouldn't be disturbed. We could
             also add other invariants here if we know them. *)
          Acc.empty ASSEMBLY_CTX M.all_unknown ++
          EBX ++
          EBP

      (* val () = print ("Starting acc: " ^ Acc.debug_string acc ^ "\n") *)

      (* All blocks have a rung at the front, even the initial one.
         (In the case of the initial one, we set the initial IP so
         that it starts right after the rung, since we can't control
         our registers such that we actually end up entering it. No
         block should try to jump to the init block again, but it would
         work.) *)
      val acc = acc ++ SI
      val acc = acc // DEC SI // JNZ 0w0
      val () =
        (* Sanity check. Alternatively, we could just return this address.
           It's only used to skip over the rung for the initial block. *)
        if Acc.insbytes acc = RUNG_SIZE then ()
        else raise ToX86 "bug: expected rung to be a specific size"

      (* Record the offset of that 0w0 to be rewritten to a real jump
         to the next rail. *)
      val () = next_jumps := (Acc.insbytes acc - 1) :: !next_jumps
      val acc = acc -- SI

      (* Note: This assumes we never enter blocks other than through
         the rung, which is true today but could be broken by reasonable
         optimizations (e.g. direct forward jumps). Knowing we have
         some register with 0 in it is pretty useful. *)
      val acc =
        if is_initial
        then acc
        else acc ?? learn_reg16 M.ESI (Word16.fromInt 0)

      fun docmds (acc, nil) =
        (* If we got here, then execution continued to the end
           of the block, so we need to explicitly jump to the
           next one.

           PERF: We can usually fall through to the next block
           (e.g., not execute the JNZ) instead. (Note that the
           very last block must explicitly jump in order to
           overflow the IP.) *)
        let
          val acc = acc ++ EAX ++ ESI
          val acc = Tactics.load_ax16 acc (Word16.fromInt 0) //
            PUSH AX //
            POP SI //
            (* We specifically zero it then INC so that we know
               the zero flag is clear here. *)
            INC SI ?? learn_reg16 M.ESI (Word16.fromInt 1) //
            (* Keep SI claimed, though it is probably moot. *)
            JNZ 0w0 -- EAX
        in
          next_jumps := (Acc.insbytes acc - 1) :: !next_jumps;
          acc
        end

        | docmds (acc, cmd :: cmds) =
        (case onecmd acc cmd of
           Finished acc => acc
         | Continue acc => docmds (acc, cmds))

      val acc = docmds (acc, cmds)

      fun debug_print () =
        let val insns = Acc.insns acc
        in
          print ("#" ^ Int.toString (getlabelnum labelnum current_lab) ^ ". " ^
                 current_lab ^ ":\n");
          (* XXX print next jumps, etc. *)
          app (fn ins => print ("   " ^ insstring ins ^ "\n")) insns;
          print "\n"
        end

    in
      debug_print ();
      (current_lab, Acc.encoded acc, !next_jumps)
    end

  (* Attempt to lay out the assembly program. The labels in the order
     they appear become the blocks (each one is a rung). The layout
     may not be valid, so the driver needs to check for several
     problems that could occur, and then call layout_round again
     with an adjusted program. *)
  fun layout_round (blocks : A.explicit_block list,
                    frame_stack_start : int,
                    initial_label : string) =
    let
      (* Each block will have a rung of the ladder precede it. We
         give each of these a number, in sequence, so that we
         can use these numbers as absolute addresses, and compute
         relative addresses by subtracting the current address. *)
      val labels =
        Vector.fromList (map (fn (A.Block { name, ... }) => name) blocks)
      val labelnum = Vector.foldli (fn (i, lab, m) =>
                                    SM.insert (m, lab, i)) SM.empty labels
      val num_labels = Vector.length labels

      val xblocks = map (fn (block as A.Block { name, ... }) =>
                         layout_block { labelnum = labelnum,
                                        num_labels = Vector.length labels,
                                        frame_stack_start = frame_stack_start,
                                        is_initial = (name = initial_label),
                                        block = block }) blocks
    in
      xblocks
    end

  fun w8vtos v : string =
    CharVector.tabulate (Word8Vector.length v,
                         fn i => chr (Word8.toInt (Word8Vector.sub (v, i))))

  fun tox86 (A.Program { blocks, frame_stack_start, datasegment }) =
    let
      (* XXX probably need to move initial block into the middle,
         like repetedly advance it (or binary search) until it's printable? *)
      val initial_label =
        case blocks of
          nil => raise ToX86 "ASM program is empty? Impossible!"
        | A.Block { name, ... } :: _ => name

      val xblocks : (string * Word8Vector.vector * int list) list =
        layout_round (blocks, frame_stack_start, initial_label)

      val total = foldl (fn ((l, v, _), b) =>
                         Word8Vector.length v + b) 0 xblocks
      val () = print ("Total code bytes before stretching: " ^
                      Int.toString total ^ "\n")
      val () = app (fn (l, v, _) =>
                    print (l ^ ": " ^ w8vtos v ^ "\n")) xblocks

      val cs = Segment.empty ()
      val () = Segment.set_repeating_string cs 0 65536 "(CODE SEGMENT)"

      (* OK, now we want to insert our blocks into the code segment
         and patch up the jumps. This may not be possible, in which case
         we'll make some adjustment (like splitting a block) and then
         start again.

         - The blocks must appear in the order they occur, since addressing
           is relative.
         - We have to fill in the jump offsets. These currently always
           go to the beginning of the next block.
         - If a jump offset can't be output because it's not printable,
           then we'll have to try again.

         Note that for the jump instructions, the displacement is measured
         from the address of the next instruction, so for example JMP 0
         just executes the next instruction. *)

      (* We should probably split blocks > 126 bytes first; a single block
         greater than the whole segment would cause confusing failures
         in the block below (not that we would succeed after splitting!) *)

      (* This is filled in with the actual start of the initial block
         (not its rung), which we'll use to kick off the execution. *)
      val init_addr = ref (NONE : Word16.word option)
      (* Current offset within code segment; this is the first
         address where we can acceptably place the next block.

         We start this at some value like 0x2020 in order to ensure
         that init has a printable address. *)
      val start_ip = 0x2020

      (* XXX could easily pass this instead of it being a ref *)
      val cur = ref start_ip

      (* Fill the rest of the code segment, such that when control
         ends up on !cur, it makes its way back to the beginning of
         cs, and update cur so that it's near the beginning of the
         segment. This may involve filling the remainder of the
         segment with unconditional jumps.

         *)
      fun fill_rest () =
        raise ToX86 "unimplemented"

      (* Control flow is at !cur, and we want to execute the
         block at the head of this list. The previous block
         has already been patched to jump to !cur. *)
      fun place ((xb as (lab, vec, jmps)) :: rest) : unit =
        let val len = Word8Vector.length vec
        in
          print ("place w/ cur=" ^ Int.toString (!cur) ^ " block " ^
                 lab ^ " of length " ^ Int.toString len ^ "\n");
          if !cur + len > 65536
          then
            let in
              print " ... would overflow.\n";
              fill_rest ();
              place (xb :: rest)
            end
          else
            let
              val abs_jmps = map (fn j => !cur + j) jmps
              (* Earliest we could place the next one is right after
                 this block ends. *)
              val min_pos = ref (!cur + len)
              (* But it also has to be far enough for the jumps to
                 reach it with printable displacements. *)
              val () = app (fn j =>
                            let
                              val srcip = j + 1
                              val disp = !min_pos - srcip
                            in
                              (* XXX 0x20 *)
                              if disp < 0
                              then min_pos := !min_pos - disp
                              else ()
                            end) abs_jmps
              val next_cur = !min_pos
            in
              if next_cur >= 65536
              then raise ToX86 "need to handle the case that next_cur overflows"
              else ();

              print ("write " ^ lab ^ " to " ^ Int.toString (!cur) ^ ".\n");
              Segment.set_vec cs (!cur) vec;
              (* Lock everything except for the locations we need to
                 update (jumps) *)
              Segment.lock_range cs (!cur) len;
              app (Segment.unlock_idx cs) abs_jmps;

              (* Fill in my jumps to point to next_cur. *)
              app (fn j =>
                   let
                     val srcip = j + 1
                     val disp = next_cur - srcip
                   in
                     (* XXX need to check displacement < 0x20 too. *)
                     if disp > 0x7e
                     then raise ToX86 ("In 'place', needed to write " ^
                                       "displacement larger than 0x7e: " ^
                                       Int.toString disp)
                     else if disp < 0
                          then raise ToX86 ("In 'place', negative " ^
                                            "displacement?! " ^
                                            Int.toString disp)
                          else
                            let in
                              Segment.set_idx cs j (Word8.fromInt disp);
                              Segment.lock_idx cs j
                            end
                   end) abs_jmps;

              (* Now control flow will be at next_cur. *)
              cur := next_cur;
              place rest
            end
        end
        | place nil =
        let in
          print ("Out of blocks with cur=" ^ Int.toString (!cur) ^
                 " and start_ip=" ^ Int.toString start_ip ^ "\n");
          (* We've used up all the blocks and execution is at !cur.
             Need to get control back to start_ip. *)
          if !cur <= start_ip
          then
            let
              val disp = start_ip - !cur
            in
              if disp = 0
              then print " .. exact hit!\n"
              else
                (* PERF use jumps, duhhh *)
                (* Pad with "INC AX".

                   Assumes AX is not holding any interesting
                   values between blocks.

                   A better one-byte padding might be the
                   segment prefix bytes, which don't do anything
                   if the next instruction is DEC SI. *)
                let in
                  Segment.set_idx cs (!cur) 0wx40;
                  Segment.lock_idx cs (!cur);
                  cur := !cur + 1;
                  place nil
                end
            end
          else
            let in
              print " .. gotta wrap\n";
              fill_rest ();
              place nil
            end
          end

      val () = place xblocks


      (* XXX: Need to check that this is printable, and move the
         initial block if it's not! *)
      val init_ip =
        case !init_addr of
          NONE => raise ToX86 ("The initial block " ^ initial_label ^
                               "was never written to the code segment!?")
        | SOME ia => ia

      (* val cs =
         raise ToX86 "still need to do various things to construct cs" *)
    in
      { cs = Segment.extract cs,
        init_ip = init_ip,
        ds = datasegment }
    end

end
