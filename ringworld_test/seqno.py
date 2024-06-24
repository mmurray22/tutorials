from scapy.all import *

TYPE_SEQNO = 0x820
TYPE_MYTUNNEL = 0x1212
TYPE_IPV4 = 0x0800

class MyTunnel(Packet):
    name = "MyTunnel"
    fields_desc = [
        ShortField("pid", 0),
        ShortField("dst_id", 0)
    ]
    def mysummary(self):
        return self.sprintf("pid=%pid%, dst_id=%dst_id%")

class UpdateTail(Packet):
   fields_desc = [ IntField("tail", 0)]


class SeqNo(Packet):
   fields_desc = [ ByteField("server_id", 0),
                   IntField("seq_no", 0)]

bind_layers(Ether, SeqNo, type=TYPE_SEQNO)
bind_layers(SeqNo, UpdateTail)
bind_layers(UpdateTail, MyTunnel)
bind_layers(MyTunnel, IP, pid=TYPE_IPV4)
