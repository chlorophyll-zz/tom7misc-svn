structure ExCSS :>
  sig
    type bytevector = Word8.word Vector.vector

    (* keys are 6 bytes *)
    type key = bytevector

    (* an example player key *)
    val playerkey : key

    (* takes encrypted disk key and player key, 
       returns decrypted disk key *)
    val titlekey1 : key * key -> key
      
    (* takes encrypted title key and disk key, 
       returns decrypted title key *)
    val titlekey2 : key * key -> key
      
    (* takes an encrypted title key and encrytped disk key,
       returns a decrypted title key *)
    val detitlekey : key * key -> key
      
    (* takes a 2048-byte sector and decryption key, 
       returns decrypted sector *)
    val descramble : bytevector * key -> bytevector
      
  end =
struct

  exception Unimplemented and Impossible
  open Vector
    
  (* functional vector modify *)
  fun modify (v : 'a vector,
              i : int,
              a : 'a) : 'a vector =
    mapi (fn (ii, aa) => if ii = i then a else aa) (v, 0, NONE)
    
  structure W8 = Word8
  structure W32 = Word32
    
  type bytevector = W8.word Vector.vector
    
  val w32 = W32.fromInt o W8.toInt
  val w8  = W8.fromInt o W32.toIntX
    
  type key = W8.word vector

  val playerkey : bytevector = 
    fromList [0wx51, 0wx67, 0wx67, 0wxC5, 0wxE0, 0wx00]
    
local 
  val table1 = Vector.fromList [
0x33,0x73,0x3b,0x26,0x63,0x23,0x6b,0x76,0x3e,0x7e,0x36,0x2b,0x6e,0x2e,0x66,0x7b,
0xd3,0x93,0xdb,0x06,0x43,0x03,0x4b,0x96,0xde,0x9e,0xd6,0x0b,0x4e,0x0e,0x46,0x9b,
0x57,0x17,0x5f,0x82,0xc7,0x87,0xcf,0x12,0x5a,0x1a,0x52,0x8f,0xca,0x8a,0xc2,0x1f,
0xd9,0x99,0xd1,0x00,0x49,0x09,0x41,0x90,0xd8,0x98,0xd0,0x01,0x48,0x08,0x40,0x91,
0x3d,0x7d,0x35,0x24,0x6d,0x2d,0x65,0x74,0x3c,0x7c,0x34,0x25,0x6c,0x2c,0x64,0x75,
0xdd,0x9d,0xd5,0x04,0x4d,0x0d,0x45,0x94,0xdc,0x9c,0xd4,0x05,0x4c,0x0c,0x44,0x95,
0x59,0x19,0x51,0x80,0xc9,0x89,0xc1,0x10,0x58,0x18,0x50,0x81,0xc8,0x88,0xc0,0x11,
0xd7,0x97,0xdf,0x02,0x47,0x07,0x4f,0x92,0xda,0x9a,0xd2,0x0f,0x4a,0x0a,0x42,0x9f,
0x53,0x13,0x5b,0x86,0xc3,0x83,0xcb,0x16,0x5e,0x1e,0x56,0x8b,0xce,0x8e,0xc6,0x1b,
0xb3,0xf3,0xbb,0xa6,0xe3,0xa3,0xeb,0xf6,0xbe,0xfe,0xb6,0xab,0xee,0xae,0xe6,0xfb,
0x37,0x77,0x3f,0x22,0x67,0x27,0x6f,0x72,0x3a,0x7a,0x32,0x2f,0x6a,0x2a,0x62,0x7f,
0xb9,0xf9,0xb1,0xa0,0xe9,0xa9,0xe1,0xf0,0xb8,0xf8,0xb0,0xa1,0xe8,0xa8,0xe0,0xf1,
0x5d,0x1d,0x55,0x84,0xcd,0x8d,0xc5,0x14,0x5c,0x1c,0x54,0x85,0xcc,0x8c,0xc4,0x15,
0xbd,0xfd,0xb5,0xa4,0xed,0xad,0xe5,0xf4,0xbc,0xfc,0xb4,0xa5,0xec,0xac,0xe4,0xf5,
0x39,0x79,0x31,0x20,0x69,0x29,0x61,0x70,0x38,0x78,0x30,0x21,0x68,0x28,0x60,0x71,
0xb7,0xf7,0xbf,0xa2,0xe7,0xa7,0xef,0xf2,0xba,0xfa,0xb2,0xaf,0xea,0xaa,0xe2,0xff]

  val table2 = Vector.fromList [
0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x09,0x08,0x0b,0x0a,0x0d,0x0c,0x0f,0x0e,
0x12,0x13,0x10,0x11,0x16,0x17,0x14,0x15,0x1b,0x1a,0x19,0x18,0x1f,0x1e,0x1d,0x1c,
0x24,0x25,0x26,0x27,0x20,0x21,0x22,0x23,0x2d,0x2c,0x2f,0x2e,0x29,0x28,0x2b,0x2a,
0x36,0x37,0x34,0x35,0x32,0x33,0x30,0x31,0x3f,0x3e,0x3d,0x3c,0x3b,0x3a,0x39,0x38,
0x49,0x48,0x4b,0x4a,0x4d,0x4c,0x4f,0x4e,0x40,0x41,0x42,0x43,0x44,0x45,0x46,0x47,
0x5b,0x5a,0x59,0x58,0x5f,0x5e,0x5d,0x5c,0x52,0x53,0x50,0x51,0x56,0x57,0x54,0x55,
0x6d,0x6c,0x6f,0x6e,0x69,0x68,0x6b,0x6a,0x64,0x65,0x66,0x67,0x60,0x61,0x62,0x63,
0x7f,0x7e,0x7d,0x7c,0x7b,0x7a,0x79,0x78,0x76,0x77,0x74,0x75,0x72,0x73,0x70,0x71,
0x92,0x93,0x90,0x91,0x96,0x97,0x94,0x95,0x9b,0x9a,0x99,0x98,0x9f,0x9e,0x9d,0x9c,
0x80,0x81,0x82,0x83,0x84,0x85,0x86,0x87,0x89,0x88,0x8b,0x8a,0x8d,0x8c,0x8f,0x8e,
0xb6,0xb7,0xb4,0xb5,0xb2,0xb3,0xb0,0xb1,0xbf,0xbe,0xbd,0xbc,0xbb,0xba,0xb9,0xb8,
0xa4,0xa5,0xa6,0xa7,0xa0,0xa1,0xa2,0xa3,0xad,0xac,0xaf,0xae,0xa9,0xa8,0xab,0xaa,
0xdb,0xda,0xd9,0xd8,0xdf,0xde,0xdd,0xdc,0xd2,0xd3,0xd0,0xd1,0xd6,0xd7,0xd4,0xd5,
0xc9,0xc8,0xcb,0xca,0xcd,0xcc,0xcf,0xce,0xc0,0xc1,0xc2,0xc3,0xc4,0xc5,0xc6,0xc7,
0xff,0xfe,0xfd,0xfc,0xfb,0xfa,0xf9,0xf8,0xf6,0xf7,0xf4,0xf5,0xf2,0xf3,0xf0,0xf1,
0xed,0xec,0xef,0xee,0xe9,0xe8,0xeb,0xea,0xe4,0xe5,0xe6,0xe7,0xe0,0xe1,0xe2,0xe3]

in

  fun tab0 0  = 5
    | tab0 1  = 0
    | tab0 2  = 1
    | tab0 3  = 2
    | tab0 4  = 3
    | tab0 5  = 4
    | tab0 6  = 0
    | tab0 7  = 1
    | tab0 8  = 2
    | tab0 9  = 3
    | tab0 10 = 4
    | tab0 _  = raise Impossible

  fun tab3 0 = 0wx00 : W32.word
    | tab3 1 = 0wx24
    | tab3 2 = 0wx49
    | tab3 3 = 0wx6d
    | tab3 4 = 0wx92
    | tab3 5 = 0wxb6
    | tab3 6 = 0wxdb
    | tab3 7 = 0wxff
    | tab3 n = tab3 (n mod 8)

  (* substitutions above *)
  fun tab1 n = W32.fromInt (Vector.sub (table1, n))
  fun tab2 n = W32.fromInt (Vector.sub (table2, n))

  (* reverse bits *)
  fun tab4 n = 
    let
      fun set i = W32.<<(0w1, Word.fromInt i)
      fun b i = (if W32.andb(n, set i) > 0w0 then
                   set (7 - i) else 0w0)
    in
      b 0 + b 1 + b 2 + b 3 + b 4 + b 5 + b 6 + b 7
    end

  (* reverse bits, then not *)
  fun tab5 n = 
    W32.xorb(tab4 n, 0wxFF)

  val tab1w = tab1 o W32.toIntX
  val tab2w = tab2 o W32.toIntX
  val tab3w = tab3 o W32.toIntX

end

fun report s l =
	 let
		  val res = List.foldl (fn (a,b) => b ^ " " ^ Util.w32hs a) "" l
	 in
		  print ("% " ^ s ^ ": " ^ res ^ "\n")
	 end

(* this functional takes a table as its
   first parameter. It is used to generate
   titlekey1 and titlekey2 *)
fun decode table (enc    : key,
                  pk     : key) : key =
  let

    fun im x = w32 (sub (pk, x))
    val t1 = im 0 + 0w256
    val t2 = im 1
    val t3 = im 5 * (0w256*0w256*0w256) +
             im 4 * (0w256*0w256) +
             im 3 * (0w256) +
             im 2
    val t4 = im 2 mod 0w8

(* 	 val _ = report "decode_1" [ t1, t2, t3, t4 ] *)

    val t3 = (t3 + 0w4) * 0w2 - t4

    fun l1 (_, 5, k) = Vector.fromList (rev k)
      | l1 ((t1, t2, t3, t5), n, k) = 
      let
        val t4 = W32.xorb (tab3w t1, tab2w t2) 
        val t2 = t1 div 0w2
        val t1 = W32.xorb(W32.<< (W32.andb(t1, 0w1), 0w8), t4)
        val t4 = tab4 t4
        val t6 = 
          (W32.xorb(W32.xorb(W32.xorb (t3 div 0w8, t3) div 0w2, t3) div 0w256,
                    t3) div 0w32) mod 0w256
        val t3 = W32.orb(t3 * 0w256, t6)
        val t6 = table t6
        val t5 = t5 + t6 + t4
        val res = t5 mod 0w256
        val t5 = t5 div 0w256
      in
        l1 ((t1, t2, t3, t5), n + 1, res :: k)
      end

    val k = l1 ((t1, t2, t3, 0w0), 0, nil)

(*	 val _ = report "decode_k" (Vector.foldr op:: nil k) *)

    fun l2 (~1, key) = key : W8.word vector
      | l2 (n, key) =
      l2 (n - 1,
          modify (key, tab0 (n + 1),
                  W8.fromInt
                  (W32.toInt
                   (W32.xorb (sub (k, tab0 (n + 1)),
                              W32.xorb (tab1 (W8.toInt (sub (key, 
                                                             tab0 (n + 1)))),
                                        w32 (sub (key, tab0 n))))))))
  in
    (l2 (9, enc))
  end

val titlekey1 = decode tab4
val titlekey2 = decode tab5

fun detitlekey (tkey : key, dkey : key) : key =
  titlekey2 (tkey,
             titlekey1 (playerkey, 
                        dkey))

fun descramble (sector  : W8.word vector,
                dec_key : key) =
  let
    fun sec x = w32 (sub (sector, x))
    fun key x = w32 (sub (dec_key, x))

    val t1 = W32.orb(0wx100,W32.xorb(key 0, sec 0x54))
    val t2 = W32.xorb(key 1, sec 0x55)

    val t3 = W32.xorb
      (key 5 * (0w256*0w256*0w256) +
       key 4 * (0w256*0w256) +
       key 3 * (0w256) +
       key 2,
       sec 0x59 * (0w256*0w256*0w256) +
       sec 0x58 * (0w256*0w256) +
       sec 0x57 * (0w256) +
       sec 0x56)

    val t4 = t3 mod 0w8

    val t3 = (t3 + 0w4) * 0w2 - t4
      
	 val _ = report "descramble_1" [t1, t2, t3, t4]

	 val r = ref 0
	 fun ++ x = (x := (!x + 1); !x)

    fun foldme (_, b, ((t1, t2, t3, t5), l)) =
      let
			 val _ = (++ r > 10 andalso
						 ! r < 20) andalso (report "foldme" [t1, t2, t3, t5]; true)

        val t4 = W32.xorb(tab2w t2, tab3w t1)
        val t2 = t1 div 0w2
        val t1 = W32.xorb(W32.andb(t1, 0w1) * 0w256, t4)
        val t4 = tab5 t4
        val t6 = 
          (W32.xorb(W32.xorb(W32.xorb (t3 div 0w8, t3) div 0w2, t3) div 0w256,
                    t3) div 0w32) mod 0w256
        val t3 = W32.orb(t3 * 0w256, t6)
          
        val t6 = tab4 t6

        val t5 = t4 + t5 + t6

		  val oo = W8.xorb(w8 (tab1 (W8.toInt b)), w8 t5)

		  val _ = (++ r > 10 andalso
					  ! r < 20) andalso (report "folduu" [t1, t2, t3, t5, t6,
																	  W32.fromInt (W8.toInt oo)]; true)

      in
        ( (t1, t2, t3, t5 div 0w256),
			oo :: l )
      end

  in

    Vector.concat [Vector.extract (sector, 0, SOME 0x80),
                   Vector.fromList (rev (#2
                                         (Vector.foldli foldme 
                                          ((t1, t2, t3, 0w0), nil)
                                          (sector, 0x80, NONE))))]

  end

end
