module Make (Net : Mirage_net.S) : sig
  type lease = Dhcp_wire.pkt

  type t

  val connect : ?xid:Cstruct.uint32 -> ?options:Dhcp_wire.dhcp_option list ->
    ?requests:Dhcp_wire.option_code list -> Net.t -> (t * lease Lwt_stream.t) Lwt.t
  (** [connect ~xid ~options ~requests net] starts a DHCP client communicating
      over the network interface [net].  The client will attempt to get a DHCP
      lease at least once, and will return any leases obtained in the stream
      returned by [connect]. The [options] are the DHCP options sent by the
      client in the DHCP DISCOVER and DHCP REQUEST. The [requests] will be
      transmitted as DHCP parameter request also in the DHCP DISCOVER and DHCP
      REQUEST. *)

  val input : t -> (Cstruct.t -> unit Lwt.t) -> Cstruct.t -> unit Lwt.t
  (** [input t k buf] handles an ethernet frame [buf]. If [buf] is not a dhcp
      message it is forwarded to [k]. *)

  val initiate_renew : t -> unit Lwt.t
end
