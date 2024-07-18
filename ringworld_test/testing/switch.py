#!/usr/bin/env python3
import sys
import time
from scapy.fields import *
from headers import *
setup_dir = os.path.realpath(os.path.dirname(__file__))
sys.path.append(setup_dir + "/dist-systems-group/Scripts/scripts/util/")
from ssh_util import *


NUM_SWITCHES = 4
RECEIVE_SCRIPT = "./receive.py"

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
    # Start by executing the receive command in the background
    receive_thread = executeNonBlockingCommand(RECEIVE_SCRIPT)
    receive_thread.start()
    print("Just executed the async receive script") 
    # Send control packet around to create global counter
    addr = socket.gethostbyname("10.0.4.4")
    dst_id=0
    iface = get_if()
    print("This is the control packet, being sent with dst_id = 0, so it should be sent forever") 
    pkt =  Ether(src=get_if_hwaddr(iface), dst='ff:ff:ff:ff:ff:ff')
    pkt = pkt / Cntrl() / MyTunnel(dst_id=dst_id) / IP(dst=addr)
    pkt.show2()
    sendp(pkt, iface='eth0')

if __name__ == '__main__':
    main()
