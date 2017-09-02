structure Segments :> SEGMENTS =
struct

  exception Segments of string

  datatype segment =
    Segment of { name: string,
                 gates: (LatLon.pos * LatLon.pos) Vector.vector }

  fun parse_xml xml =
    let
      datatype tree = datatype XML.tree

      (* Do this in two passes, first getting rid of extraneous XML
         stuff. *)
      datatype stree =
        Folder of string * stree list
      | Placemark of string * (real * real) list

      fun getchildname children =
        case List.mapPartial (fn Elem (("name", _), body) => SOME body
                              | _ => NONE) children of
          [[Text name]] => name
        | [nil] => ""
        | _ => raise Segments ("Expected a single <name> tag as an " ^
                               "immediate child.")

      fun process (Text _) = nil
        | process (Elem (("Folder", _), children)) =
        [Folder (getchildname children, List.concat (map process children))]
        | process (elt as Elem (("Placemark", _), children)) =
        let
          val name = getchildname children
          val coordstring = case XML.firstleaf "coordinates" elt of
            NONE => raise Segments "Expected <coordinates> in <Placemark>"
          | SOME c => c
          val coords = String.tokens StringUtil.whitespec coordstring
          val coords = map (map Real.fromString o
                            String.tokens (StringUtil.ischar #",")) coords
          val coords = map (fn [SOME lat, SOME lon, SOME elev] => (lat, lon)
                            | _ => raise Segments
                            ("Bad lat,lon,elev in <coordinates>: " ^
                             coordstring)) coords
        in
          [Placemark (name, coords)]
        end
        | process (Elem (_, children)) = List.concat (map process children)

      val strees : stree list = process xml

      (* A segment consists of a folder with placemarks in it. We can
         ignore outer-level folders.

         Note this function always takes a Folder, so maybe we should
         just have it take the folder args *)
      fun getsegfolders (Folder (name, nil)) = nil
        | getsegfolders (Folder (name, trees as (Placemark _ :: _))) =
        let
          fun get_all_places acc nil = rev acc
            | get_all_places acc (Placemark p :: rest) =
            get_all_places (p :: acc) rest
            | get_all_places acc (Folder (f, _) :: _) =
            raise Segments ("Malformed segments KML: Saw a folder '" ^ f ^
                            "' along side placemarks (inside the folder '" ^
                            name ^ "')")
        in
          [(name, get_all_places nil trees)]
        end
        | getsegfolders (Folder (name, trees as (Folder (ff, _) :: _))) =
        let
          fun one_folder (f as Folder _) = getsegfolders f
            | one_folder (Placemark _) =
            raise Segments ("Malformed segments KML: Saw a folder '" ^ ff ^
                            "' along side placemarks (inside the folder '" ^
                            name ^ "')")
        in
          List.concat (map one_folder trees)
        end
        | getsegfolders _ = raise Segments "impossible"

      (* XXX this allows a single segment at toplevel... ok? *)
      val segfolders = getsegfolders (Folder ("toplevel", strees))

      datatype gatenum = Start | End | Num of int
      fun gatestring Start = "Start"
        | gatestring End = "End"
        | gatestring (Num n) = "Num " ^ Int.toString n
      fun parsegates (name, polys as ((first, _) :: _)) =
        (case String.fields (StringUtil.ischar #":") first of
           [code, _] =>
             let
               (* Expect all the polys to share the same name prefix. *)
               val prefix = code ^ ":"
               fun norm s =
                 StringUtil.lcase (StringUtil.losespecr StringUtil.whitespec s)
               fun deprefix pname =
                 case Option.map norm (StringUtil.removehead prefix pname) of
                   NONE => raise Segments ("poly needs to have the same " ^
                                           "prefix (" ^ prefix ^ ") as its " ^
                                           "siblings; got " ^ pname)
                 | SOME "start" => Start
                 | SOME "end" => End
                 | SOME n =>
                     (case Int.fromString n of
                        NONE => raise Segments ("Expected start/end/num; " ^
                                                "got " ^ n ^ " (in " ^ name ^
                                                ")")
                      | SOME num => Num num)

               val numbered = ListUtil.mapfirst deprefix polys

               (* Find the gate from the 5-sided flag polygon, or abort.
                  See segments-sig. *)
               fun decodegate pname [a as (ax, ay), b, c, d, e, f as (fx, fy)] =
                 (* Allow six points if the last one is almost exactly
                    the same as the first. *)
                 if Real.abs (ax - fx) < 0.0000001 andalso
                    Real.abs (ay - fy) < 0.0000001
                 then decodegate pname [a, b, c, d, e]
                 else raise Segments
                   ("Six-vertex polygon is only allowed if the " ^
                    "first and last are the same point (in " ^
                    name ^ "/" ^ pname ^ ")")
                 | decodegate pname [a, b, c, d, e] =
                   let
                     (* XXXX find the right pair *)
                   in
                     (LatLon.fromdegs { lat = #1 a, lon = #2 a },
                      LatLon.fromdegs { lat = #1 b, lon = #2 b })
                   end

                 | decodegate pname l =
                   raise Segments
                     ("Expected five-vertex polygon in " ^ name ^ "/" ^
                      pname ^ "; got " ^ Int.toString (length l))

               val decoded =
                 map (fn (g, coords) =>
                      (g, decodegate (gatestring g) coords)) numbered

               fun split (SOME start, _, _) ((Start, _) :: _) =
                     raise Segments ("Duplicate starts in " ^ name)
                 | split (NONE, nn, ee) ((Start, coords) :: rest) =
                     split (SOME coords, nn, ee) rest
                 | split (_, _, SOME e) ((End, _) :: _) =
                     raise Segments ("Duplicate ends in " ^ name)
                 | split (ss, nn, NONE) ((End, coords) :: rest) =
                     split (ss, nn, SOME coords) rest
                 | split (ss, nn, ee) ((Num n, coords) :: rest) =
                     split (ss, (n, coords) :: nn, ee) rest
                 | split (NONE, _, _) nil =
                     raise Segments ("Missing start in " ^ name)
                 | split (_, _, NONE) nil =
                     raise Segments ("Missing end in " ^ name)
                 | split (SOME s, nn, SOME e) nil =
                     let
                       val nn = ListUtil.sort (Util.byfirst Int.compare) nn
                       (* XXX check that it starts at 1? *)
                       fun gap_of_one ((a, _), (b, _)) = a + 1 = b
                       val () =
                         if ListUtil.alladjacent gap_of_one nn
                         then ()
                         else raise Segments ("gap or duplicate numbers in " ^
                                              "segment " ^ name)
                       val nn = map #2 nn
                     in
                       s :: (nn @ [e])
                     end

               val ordered = split (NONE, nil, NONE) decoded
             in
               Segment { name = name,
                         gates = Vector.fromList ordered }
             end
         | _ => raise Segments ("poly should have a name like code:start; " ^
                                "got '" ^ first ^ "'"))
        | parsegates (name, nil) =
           raise Segments ("empty segment '" ^ name ^ "'? impossible?")

      (* Now interpret the segments. *)
      val gates = map parsegates segfolders
    in
      gates
    end

  fun parse_string contents =
    let val xml = XML.parsestring contents
      handle XML.XML s => raise Segments ("Malformed xml: " ^ s)
    in
      parse_xml xml
    end

  fun parse_file f = parse_string (StringUtil.readfile f)


end