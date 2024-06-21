from scapy.all import *

TYPE_SEQNO = 0x820

class SeqNo(Packet):
   fields_desc = [ ByteField("server_id", 0),
                   IntField("seq_no", 0)]

bind_layers(Ether, SeqNo, type=TYPE_SEQNO)
bind_layers(SeqNo, IP)


