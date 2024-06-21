#!/usr/bin/env python3
import sys
import time
from scapy.fields import *
from seqno import *

NUM_SWITCHES = 4

def get_if():
    ifs=get_if_list()
    iface=None # "h1-eth0"
    for i in get_if_list():
        if "eth0" in i:
            iface=i
            break;
    if not iface:
        print("Cannot find eth0 interface")
        exit(1)
    return iface

def main():

    # Send local rack level packets
    i = 0
    addr = socket.gethostbyname('10.0.1.1')
    while i <= 3:
        try:
            pkt = Ether(dst='ff:ff:ff:ff:ff:ff', src=get_if_hwaddr('eth0'))
            pkt = pkt / SeqNo(server_id=1)
            pkt = pkt / IP(dst=addr) / UDP(dport=4321, sport=1234)
            pkt.show2()
            sendp(pkt, iface='eth0')
            i += 1
            time.sleep(1)
        except KeyboardInterrupt:
            sys.exit()

    # Send control packet around to create global counter
    addr = socket.gethostbyname("10.0.3.3")
    iface = get_if()
    print("sending on interface %s to %s" % (iface, str(addr))) 
    pkt = Ether(dst='ff:ff:ff:ff:ff:ff', src=get_if_hwaddr('eth0'))  
    pkt = pkt / SeqNo(server_id=0)	    
    pkt = pkt / IP(dst=addr) / UDP(dport=4321, sport=1234)
    pkt.show2()
    sendp(pkt, iface='eth0')

if __name__ == '__main__':
    main()
