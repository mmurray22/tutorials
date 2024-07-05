/* -*- P4_16 -*- */
// Credit: Base code come from p4 tutorial exercises
#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_TUNNEL = 0x1212;
const bit<16> TYPE_IPV4  = 0x800;
const bit<16> TYPE_SEQ_NO_REQ = 0x820;
const bit<16> TYPE_ACK = 0x840;
#define STORAGE_SERVERS 1
#define MAX_OUTSTANDING_APPENDS 10
#define MAX_HOPS 10
#define MAX_PORTS 8
#define NUM_SWITCHES 4

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;

typedef bit<48> time_t;

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<8>    diffserv;
    bit<16>   totalLen;
    bit<16>   identification;
    bit<3>    flags;
    bit<13>   fragOffset;
    bit<8>    ttl;
    bit<8>    protocol;
    bit<16>   hdrChecksum;
    ip4Addr_t srcAddr;
    ip4Addr_t dstAddr;
}

// NOTE: added new header type
header myTunnel_t {
    bit<16> proto_id;
    bit<16> dst_id;
}

// Header for sequence number rack/control packet
header seq_no_t {
   // If server_id = 0, this is the control packet sent from another switch
   // Any other number indicates this is from a server in the switch's rack
   bit<8> server_id;
   // If server_id = 0, this value does not matter and will be set to the next highest local seq_no
   // If this is the control packet, this is the current global sequence number.
   bit<32> seq_no;
}

// Header for updating tail
header tail_t {
   bit<32> tail;  // Sequence number of the tail of the log
}

// Header indicating that this is an ack packet
header is_ack_t {
    bit<8> has_ack;
}

// Header for ack rack packet
header ack_t {
    bit<32> seqno_ack; // Sequence number the server is acking. 
    // DUMB APPROACH: Currently repeats the ack MAX_OUTSTANDING num of times to iterate in the seqno
    bit<32> storage_server_id; // ID of the server in the rack
}

struct metadata {
    bit<32> ack_seq_no_idx;
}

struct headers {
    ethernet_t              ethernet;
    is_ack_t                is_ack_pkt;
    ack_t[MAX_OUTSTANDING_APPENDS]    ack_tracker; // Only for in-rack packets
    seq_no_t                          seqno;
    tail_t                            update_tail;
    myTunnel_t              myTunnel;
    ipv4_t                  ipv4;
}

/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {


    register<bit<32>>(MAX_OUTSTANDING_APPENDS) idx_to_seq_no_map;    

    register<bit<32>>(1) idx;

    state start {
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);
        // TODO: Add another EtherType for counting Acks
        transition select(hdr.ethernet.etherType) {
            TYPE_TUNNEL: parse_tunnel;
	    TYPE_IPV4: parse_ipv4;
	    TYPE_SEQ_NO_REQ: parse_seqno;
	    TYPE_ACK: parse_ack;
            default: accept;
        }
    }

    state parse_ack {
	packet.extract(hdr.is_ack_pkt);
	idx.write(0, MAX_OUTSTANDING_APPENDS);
	transition parse_ack_subroutine;
    }

   state parse_ack_subroutine {
	 // TODO: Ideally would like to extract only one value each iteration (not build full array)
	packet.extract(hdr.ack_tracker.next);
	bit<32> local_idx;
	idx.read(local_idx, 0);
	local_idx = local_idx - 1;
	bit<32> seqno;
	bit<32> success;
	if (local_idx == 0) {
	    seqno = hdr.ack_tracker.last.seqno_ack;
	    meta.ack_seq_no_idx = MAX_OUTSTANDING_APPENDS + 1;
	    success = 0;
	} else {
	    bit<32> chosen_seqno;
	    idx_to_seq_no_map.read(chosen_seqno, local_idx);
	    meta.ack_seq_no_idx = chosen_seqno;
	    success = chosen_seqno - hdr.ack_tracker.last.seqno_ack;
	}
	transition select(success) {
	    0: parse_seqno; 
	    default: parse_ack_subroutine;
	}	
   }

    state parse_seqno {
	packet.extract(hdr.seqno);
 	transition parse_update_tail;
    }
    
    state parse_update_tail {
	packet.extract(hdr.update_tail);
 	transition parse_tunnel;
    }

    state parse_tunnel {
	packet.extract(hdr.myTunnel);
	transition select(hdr.myTunnel.proto_id) {
	    0x0800: parse_ipv4;
	    default: accept;
	}
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }
}

/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply {  }
}


/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr,
                  inout metadata meta,
            

    inout standard_metadata_t standard_metadata) {
    /** Registers **/
    // Sequence number registers
    register<bit<32>>(1) rack_seq_no_reg; // Rack local sequence number. Reset each time it's added to global counter
    register<bit<32>>(1) global_seq_no_reg; // Global sequence number. Updated every time control packet is received


    // Acking register: 2D array tracking outstanding appends from the rack's storage servers. 
    //(TODO) Updated each time a packet with an ack_t header is received.
    // If an outstanding append reaches a quorum of acks, it is replaced with the next highest seq_no with outstanding acks
    // and all ack entries for the servers are set to zero.
    register<bit<32>>(STORAGE_SERVERS * MAX_OUTSTANDING_APPENDS) rack_acks_reg;    

    // Tail registers
    // Latest tail tracked by switch
    // Updated either by external packet reporting higher tail or local ack counter reaching quorum threshold
    register<bit<32>>(1) log_tail_reg;
    // Locally tracks number of acks until tail can advance
    register<bit<32>>(1) log_next_tail_acks_reg;

    action drop() {
        mark_to_drop(standard_metadata);
    }

    // TODO: Make this infinite
    action ipv4_forward(macAddr_t dstAddr, egressSpec_t port) {
        standard_metadata.egress_spec = port;
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = dstAddr;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }

    table ipv4_lpm {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            ipv4_forward;
            drop;
            NoAction;
        }
        size = 1024;
        default_action = drop();
    }
   
    action myTunnel_forward(egressSpec_t port) {
	standard_metadata.egress_spec = port;
    }

    table myTunnel_exact {
	key = {
	   hdr.myTunnel.dst_id: exact;
	}
	actions = {
	   myTunnel_forward;
	   drop;
	}
	size = 1024;
	default_action = drop();
    }

    apply {
        if (hdr.seqno.isValid()) {
	    bit<32> seq_no;
	    rack_seq_no_reg.read(seq_no, 0);
	    if (hdr.seqno.server_id == 0) {
		// Updating the global sequence counter
		seq_no = seq_no + hdr.seqno.seq_no;
		hdr.seqno.seq_no = seq_no;
		global_seq_no_reg.write(0, seq_no);
	    } else {
		// Updating the rack local sequence counter
	        bit<32> global_seq_no;
		global_seq_no_reg.read(global_seq_no, 0);
		seq_no = seq_no + 1;
		rack_seq_no_reg.write(0, seq_no);
		seq_no = global_seq_no + seq_no;
		hdr.seqno.seq_no = seq_no;
	    }
        }

	if (hdr.update_tail.isValid()) {
	    bit<32> tail;
	    log_tail_reg.read(tail, 0);
	    if (hdr.update_tail.tail > tail) {
		tail = hdr.update_tail.tail;
		log_tail_reg.write(0, tail);
	    } else if (tail > hdr.update_tail.tail) {
	        hdr.update_tail.tail = tail;
	    }
	}

	if (hdr.is_ack_pkt.isValid()) { // TODO COMMENT
	    rack_acks_reg.write(MAX_OUTSTANDING_APPENDS*hdr.ack_tracker[0].storage_server_id + meta.ack_seq_no_idx, 1);
	}

	if (hdr.ipv4.isValid()) {
            ipv4_lpm.apply();
        }

 	if (hdr.myTunnel.isValid()) {
	    myTunnel_exact.apply();
	} 
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   ********************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
	apply { } // TODO: Add acking packets here for sequence counters
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   ***************
*************************************************************************/

control MyComputeChecksum(inout headers  hdr, inout metadata meta) {
     apply {
        update_checksum(
            hdr.ipv4.isValid(),
            { hdr.ipv4.version,
              hdr.ipv4.ihl,
              hdr.ipv4.diffserv,
              hdr.ipv4.totalLen,
              hdr.ipv4.identification,
              hdr.ipv4.flags,
              hdr.ipv4.fragOffset,
              hdr.ipv4.ttl,
              hdr.ipv4.protocol,
              hdr.ipv4.srcAddr,
              hdr.ipv4.dstAddr },
            hdr.ipv4.hdrChecksum,
            HashAlgorithm.csum16);
    }
}

/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
	packet.emit(hdr.seqno);
	packet.emit(hdr.update_tail);
	packet.emit(hdr.myTunnel);
        packet.emit(hdr.ipv4);
    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;
