let src = Logs.Src.create "dhcp_client_mirage"
module Log = (val Logs.src_log src : Logs.LOG)

let config_of_lease lease =
  let open Dhcp_wire in
  (* ipv4_config expects a single IP address and the information
     needed to construct a prefix.  It can optionally use one router. *)
  let address = lease.yiaddr in
  let lease_time =
    Dhcp_wire.find_ip_lease_time lease.options
    |> Option.value ~default:1800l
  in
  match Dhcp_wire.find_subnet_mask lease.options with
  | None ->
    Log.info (fun f -> f "Lease obtained with no subnet mask; discarding it");
    Log.debug (fun f -> f "Unusable lease: %a" Dhcp_wire.pp_pkt lease);
    None
  | Some subnet ->
    match Ipaddr.V4.Prefix.of_netmask ~netmask:subnet ~address with
    | Error `Msg msg ->
      Log.info (fun f -> f "Invalid address and netmask combination %s, discarding" msg);
      None
    | Ok network ->
      let valid_routers = Dhcp_wire.collect_routers lease.options in
      match valid_routers with
      | [] -> Some ((network, None), lease_time)
      | hd::_ -> Some ((network, Some hd), lease_time)

module Make (Network : Mirage_net.S) (E : Ethernet.S) (Arp : Arp.S) = struct
  open Lwt.Infix

  (* for now, just wrap a static ipv4 *)
  module DHCP = Dhcp_client_lwt.Make(Network)
  include Static_ipv4.Make(E)(Arp)

  type nonrec t =
    | Dhcp of {
        static : t;
        dhcp : DHCP.t;
        lease_stream : DHCP.lease Lwt_stream.t;
      }
    | Static of t

  let connect ?(no_init = false) ?cidr ?gateway ?options ?requests net ethernet arp =
    match cidr, no_init with
    | None, false ->
      let requests = match requests with
        | None -> Dhcp_wire.[ SUBNET_MASK; ROUTERS ]
        | Some s -> s
      in
      DHCP.connect ?options ~requests net >>= fun (dhcp, lease_stream) ->
      let configs = Lwt_stream.filter_map config_of_lease lease_stream in
      Lwt_stream.last_new configs >>= fun ((cidr, gateway), lease_time) ->
      connect ~no_init ~cidr ?gateway ethernet arp >|= fun static ->
      (* this is flawed *)
      let rec renew () =
        let sleep_time =
          Int32.(unsigned_to_int (max 1l (div lease_time 2l)))
          |> Option.value ~default:max_int
        in
        Mirage_sleep.ns (Duration.of_sec sleep_time) >>= fun () ->
        DHCP.initiate_renew dhcp >>= renew
      in
      Lwt.async renew;
      Dhcp { static; dhcp; lease_stream }
    | None, true ->
      let cidr = Ipaddr.V4.(Prefix.make 32 localhost) in
      connect ~no_init ~cidr ?gateway ethernet arp >|= fun static ->
      Static static
    | Some cidr, _ ->
      connect ~no_init ~cidr ?gateway ethernet arp >|= fun static ->
      Static static

  let input = function
    | Dhcp t ->
      fun ~tcp ~udp ~default -> DHCP.input t.dhcp (input t.static ~tcp ~udp ~default)
    | Static t ->
      fun ~tcp ~udp ~default -> input t ~tcp ~udp ~default

  let disconnect (Dhcp { static; _ } | Static static) =
    disconnect static
  let write (Dhcp { static; _ } | Static static) = write static
  let pseudoheader (Dhcp { static; _ } | Static static) = pseudoheader static
  let src (Dhcp { static; _ } | Static static) = src static
  let get_ip (Dhcp { static; _ } | Static static) = get_ip static
  [@@ocaml.warning "-3"]
  let configured_ips (Dhcp { static; _ } | Static static) = configured_ips static
  let mtu (Dhcp { static; _ } | Static static) = mtu static
end
