module Make (Net : Mirage_net.S) : sig
  type lease = Dhcp_wire.pkt

  type t = lease Lwt_stream.t

  val connect : ?xid:Cstruct.uint32 -> ?options:Dhcp_wire.dhcp_option list ->
    ?requests:Dhcp_wire.option_code list -> Net.t -> t Lwt.t
  (** [connect ~xid ~options ~requests net] starts a DHCP client communicating
      over the network interface [net].  The client will attempt to get a DHCP
      lease at least once, and will return any leases obtained in the stream
      returned by [connect]. The [options] are the DHCP options sent by the
      client in the DHCP DISCOVER and DHCP REQUEST. The [requests] will be
      transmitted as DHCP parameter request also in the DHCP DISCOVER and DHCP
      REQUEST. *)
end
