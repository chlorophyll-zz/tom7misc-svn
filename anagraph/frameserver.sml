(* Warning! This tool is intended to work in tandem with the
   JavaScript code, and makes changes to the local filesystem upon
   receiving HTTP GET requests. I have not taken any steps to prevent
   an untrusted client from writing arbitrary data. You should not run
   this on an open network. *)

structure FrameServer =
struct

  exception FrameServer of string

  datatype client_state =
    (* Unprocessed. We read until seeing two newlines. *)
    GetHeaders of string
  | Sending of Word8Vector.vector
  | Deleted

  datatype client =
    C of { socket : (INetSock.inet, Socket.active Socket.stream) Socket.sock,
           state : client_state ref }

  val clients : client list ref = ref nil
  fun delete client_sock =
    let val desc = Socket.sockDesc client_sock
    in
      clients :=
      List.filter (fn (C { socket, state, ... }) =>
                   if Socket.sameDesc (Socket.sockDesc socket, desc)
                   then
                     let in
                       state := Deleted;
                       Socket.close socket;
                       false
                     end handle _ => false
                   else true) (!clients)
    end

  fun vtos v =
    CharVector.tabulate (Word8Vector.length v,
                         fn i =>
                         chr (Word8.toInt
                              (Word8Vector.sub (v, i))))
  fun stov s =
    Word8Vector.tabulate (CharVector.length s,
                          fn i =>
                          Word8.fromInt (ord
                                         (CharVector.sub (s, i))))

  fun recv_string sock =
    case Socket.recvVecNB (sock, 1024) of
      NONE => ""
    | SOME v => vtos v

  fun date () =
    Date.fmt
    "%a, %d %b %Y %H:%M:%S %Z"
    (Date.fromTimeUniv (Time.now ()))

  fun response_ok () =
    "HTTP/1.0 200 OK\r\n" ^
    "Connection: close\r\n" ^
    "Content-Type: text/html\r\n" ^
    "Access-Control-Allow-Origin: *\r\n" ^
    "Server: FrameServer/7\r\n" ^
    "Date: " ^ date () ^ "\r\n" ^
    "\r\n" ^
    "okie dokie\n"

  fun response_fail () =
    "HTTP/1.0 404 OK\r\n" ^
    "Connection: close\r\n" ^
    "Content-Type: text/html\r\n" ^
    "Access-Control-Allow-Origin: *\r\n" ^
    "Server: FrameServer/7\r\n" ^
    "Date: " ^ date () ^ "\r\n" ^
    "\r\n" ^
    "not work ;-(\n"

  fun decode root url =
    case StringUtil.removehead root url of
      SOME rest =>
        (case StringUtil.find "/" rest of
           NONE => NONE
         | SOME idx =>
             (case StringUtil.urldecode
                (String.substring (rest, idx + 1, size rest - idx - 1)) of
                NONE => NONE
              | SOME data =>
                  let val code = String.substring (rest, 0, idx)
                  in
                    if StringUtil.all (StringUtil.charspec "a-z0-9") code
                    then SOME (code, data)
                    else NONE
                  end))
    | NONE => NONE

  fun decode_dataurl url =
    case StringUtil.removehead "data:image/png;base64," url of
      SOME base64 =>
        let in
          print (String.substring (base64, 0, 10) ^ " ... " ^
                 Int.toString (size base64) ^ "\n");
          Base64.decode base64
        end
    | NONE => NONE

  fun make_response (path, headers) =
    let
      val () = print ("Path length " ^ Int.toString (size path) ^ "\n")
    in
      case decode "/frame/" path of
        SOME (num, dataurl) =>
          (case decode_dataurl dataurl of
             SOME png =>
               let in
                 Util.for 0 12
                 (fn i =>
                  print (Int.toString (ord (String.sub(png, i))) ^ " "));
                 print "\n";
                 StringUtil.writefile ("frames/frame-" ^ num ^ ".png") png;
                 response_ok ()
               end
           | NONE =>
               let in
                 print ("Couldn't parse data url [" ^ dataurl ^ "]\n");
                 response_fail ()
               end)
      | NONE =>
      case decode "/save_atoms/" path of
        SOME (code, atoms) =>
          let in
            StringUtil.writefile ("atoms-" ^ code ^ ".js")
            ("const atom_glyphs =\n  " ^ atoms ^ ";\n");
            response_ok ()
          end
      | NONE =>
        case decode "/save_letters/" path of
          SOME (code, letters) =>
            let in
              StringUtil.writefile ("letters-" ^ code ^ ".js")
              ("const letters =\n  " ^ letters ^ ";\n");
              response_ok ()
            end
        | NONE =>
            let in
              print ("Failed to parse [" ^ path ^ "]\n");
              response_fail ()
            end
    end

  datatype headers =
    Get of string * string list
  | Bad of string

  (* Test a string to see if it's a complete set of headers.
     If so, parse them and return SOME. *)
  fun headers_done s =
    let
      (* PERF *)
      val nocr = StringUtil.losespec (StringUtil.ischar #"\r") s
    in
      case StringUtil.find "\n\n" nocr of
        NONE => NONE
      | SOME pos =>
          let
            val lines = String.fields (StringUtil.ischar #"\n")
              (String.substring (nocr, 0, pos))
            val (req, hdrs) =
              case lines of
                nil => ("ERROR", nil)
              | (h :: t) => (h, t)
          in
            (* print (req ^ "\n"); *)
            case String.tokens (StringUtil.ischar #" ") req of
              "GET" :: path :: _ => SOME (Get (path, hdrs))
            | _ => SOME (Bad nocr)
          end
    end

  (* Work on a client, known to be readable. *)
  fun do_client (C { socket, state, ... }) =
    case !state of
      GetHeaders already =>
        let
          (* PERF -- use growmonoarray, etc. *)
          val already = already ^ recv_string socket;
        in
          case headers_done already of
            NONE => state := GetHeaders already
          | SOME (Bad _) =>
              let in
                print "Bad headers.\n";
                delete socket
              end
          | SOME (Get (path, headers)) =>
              state := Sending (stov (make_response (path, headers)))
        end
    | Sending v =>
        (* Note: sendVecNB doesn't work on mingw *)
        let val x = Socket.sendVec (socket, Word8VectorSlice.full v)
        in
          if x = Word8Vector.length v
          then
            let in
              print "Finished sending.\n";
              delete socket
            end
          else
            let
              (* PERF *)
              val vv = Word8Vector.tabulate
                (Word8Vector.length v - x,
                 fn i =>
                 Word8Vector.sub (v, i + x))
            in
              state := Sending vv
            end
        end
    | Deleted =>
        let in
          print "Bug: saw deleted socket?\n";
          ()
        end

  (* Block. Returns the sockets that are ready for reading and writing.
     For the server, this means it can accept a new connection. *)
  fun ready server =
    let
      val wantread = Socket.sockDesc server ::
        List.mapPartial (fn C { socket, state = ref (GetHeaders _), ... } =>
                         SOME (Socket.sockDesc socket) | _ => NONE) (!clients)
      val wantwrite =
        List.mapPartial (fn C { socket, state = ref (Sending _), ... } =>
                         SOME (Socket.sockDesc socket) | _ => NONE) (!clients)
      val { rds, exs = _, wrs } =
        Socket.select { rds = wantread, wrs = wantwrite,
                        exs = [], timeout = NONE }

      val server_ready = ref false
      val clients_ready = ref nil

      fun proc_client desc =
        case List.find (fn (C { socket, ... }) =>
                        Socket.sameDesc (Socket.sockDesc socket, desc))
                     (!clients) of
          NONE => () (* warning? *)
        | SOME client => clients_ready := client :: !clients_ready

      fun proc_either desc =
        if Socket.sameDesc (Socket.sockDesc server, desc)
        then server_ready := true
        else proc_client desc
    in
      app proc_either rds;
      app proc_client wrs;
      { server_ready = !server_ready,
        clients_ready = !clients_ready }
    end

  fun loop server =
    let
      val { server_ready, clients_ready } = ready server
    in
      if server_ready
      then
        let val (sock, _) = Socket.accept server
        in
          print "Got connection.\n";
          clients := C { socket = sock,
                         state = ref (GetHeaders "") } :: !clients
        end
      else ();
      app do_client clients_ready;
      loop server
    end

  fun go () =
    let
      val sock = INetSock.TCP.socket()
      val port = 8000
    in
      Socket.Ctl.setREUSEADDR (sock, true);
      Socket.bind(sock, INetSock.any port);
      Socket.listen(sock, 5);
      print ("Listening on port " ^ (Int.toString port) ^ "...\n");
      loop sock
    end
end


val () = FrameServer.go ()
