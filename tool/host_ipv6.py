#!/usr/bin/env python3
"""
RTP-MIDI host over IPv6 with Bonjour advertisement.
The Mac discovers us and initiates the connection through CoreMIDI.

Usage:
  1. Disable local Mac's Network Session in Audio MIDI Setup
  2. python3 tool/host_ipv6.py
  3. On Cubase Mac: Audio MIDI Setup > Network > look for "Python Host"
     in Sessions and Directories > click Connect
"""

import socket
import struct
import subprocess
import time
import sys
import signal

CONTROL_PORT = 5004
DATA_PORT = 5005
SSRC = 0xAABBCCDD
NAME = "Python Host"

def build_ok(token, ssrc, name):
    name_bytes = name.encode() + b'\x00'
    return struct.pack('>HHIII', 0xFFFF, 0x4F4B, 2, token, ssrc) + name_bytes

def build_ck_response(ssrc, count, ck_data, local_time):
    """Build CK1 or CK2 response."""
    pkt = bytearray(36)
    struct.pack_into('>HHI', pkt, 0, 0xFFFF, 0x434B, ssrc)
    pkt[8] = count
    # Copy timestamps from received CK
    pkt[12:28] = ck_data[12:28]
    if count == 1:
        # CK1: set t2 to our local time
        t2_hi = (local_time >> 32) & 0xFFFFFFFF
        t2_lo = local_time & 0xFFFFFFFF
        struct.pack_into('>II', pkt, 20, t2_hi, t2_lo)
    return bytes(pkt)

def get_timestamp():
    return int(time.time() * 10000)

def main():
    # Start Bonjour advertisement
    print(f"Advertising '{NAME}' via Bonjour on port {CONTROL_PORT}...")
    bonjour = subprocess.Popen(
        ['dns-sd', '-R', NAME, '_apple-midi._udp', '.', str(CONTROL_PORT)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )

    def cleanup(sig=None, frame=None):
        bonjour.kill()
        sys.exit(0)
    signal.signal(signal.SIGINT, cleanup)

    # Bind sockets
    ctrl = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
    ctrl.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    ctrl.bind(('::', CONTROL_PORT))
    ctrl.settimeout(1.0)

    data = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
    data.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    data.bind(('::', DATA_PORT))
    data.settimeout(1.0)

    print(f"Listening on ports {CONTROL_PORT}/{DATA_PORT} (IPv6)")
    print("Waiting for connection from Mac...")
    print()

    remote_addr = None
    remote_ssrc = None
    connected_ports = set()

    # Wait for IN on control port
    while True:
        try:
            pkt, addr = ctrl.recvfrom(1024)
            if len(pkt) >= 16 and pkt[0:2] == b'\xff\xff':
                cmd = pkt[2:4]
                if cmd == b'IN':
                    token = struct.unpack('>I', pkt[8:12])[0]
                    remote_ssrc = struct.unpack('>I', pkt[12:16])[0]
                    remote_name = pkt[16:pkt.index(0, 16)].decode()
                    remote_addr = addr
                    print(f"Got control IN from '{remote_name}' ({addr[0]})")
                    print(f"  Remote SSRC: 0x{remote_ssrc:08x}, Token: 0x{token:08x}")

                    # Send OK
                    ok = build_ok(token, SSRC, NAME)
                    ctrl.sendto(ok, addr)
                    print("  Sent control OK")
                    connected_ports.add('control')
                    break
                elif cmd == b'CK':
                    # Clock sync on control port - respond
                    count = pkt[8]
                    if count == 0:
                        resp = build_ck_response(SSRC, 1, pkt, get_timestamp())
                        ctrl.sendto(resp, addr)
        except socket.timeout:
            continue

    # Wait for IN on data port
    print("Waiting for data IN...")
    while True:
        try:
            pkt, addr = data.recvfrom(1024)
            if len(pkt) >= 16 and pkt[0:2] == b'\xff\xff':
                cmd = pkt[2:4]
                if cmd == b'IN':
                    token = struct.unpack('>I', pkt[8:12])[0]
                    print(f"Got data IN")
                    ok = build_ok(token, SSRC, NAME)
                    data.sendto(ok, addr)
                    print("  Sent data OK")
                    connected_ports.add('data')
                    break
                elif cmd == b'CK':
                    count = pkt[8]
                    if count == 0:
                        resp = build_ck_response(SSRC, 1, pkt, get_timestamp())
                        data.sendto(resp, addr)
        except socket.timeout:
            continue

    data_addr = addr
    print(f"\nSession connected! Remote: {remote_addr[0]}")

    print("Performing rapid clock sync exchanges (like Apple does)...")

    def send_ck0():
        """Initiate a CK0 exchange."""
        t = get_timestamp()
        ck0 = bytearray(36)
        struct.pack_into('>HHI', ck0, 0, 0xFFFF, 0x434B, SSRC)
        ck0[8] = 0
        struct.pack_into('>II', ck0, 12, (t >> 32) & 0xFFFFFFFF, t & 0xFFFFFFFF)
        data.sendto(bytes(ck0), data_addr)

    def send_ck2(ck1_pkt):
        """Complete a CK exchange by sending CK2."""
        t3 = get_timestamp()
        pkt = bytearray(36)
        struct.pack_into('>HHI', pkt, 0, 0xFFFF, 0x434B, SSRC)
        pkt[8] = 2
        pkt[12:28] = ck1_pkt[12:28]  # copy t1, t2
        struct.pack_into('>II', pkt, 28, (t3 >> 32) & 0xFFFFFFFF, t3 & 0xFFFFFFFF)
        data.sendto(bytes(pkt), data_addr)

    # Do multiple rapid CK exchanges (Apple does 6+)
    for i in range(6):
        send_ck0()
        time.sleep(0.1)

    # Handle all CK responses for a few seconds
    deadline = time.time() + 5
    ck_count = 0
    while time.time() < deadline:
        try:
            pkt, addr = data.recvfrom(1024)
            if len(pkt) >= 36 and pkt[2:4] == b'CK':
                count = pkt[8]
                if count == 0:
                    # Mac initiated CK0 — respond with CK1
                    resp = build_ck_response(SSRC, 1, pkt, get_timestamp())
                    data.sendto(resp, addr)
                    ck_count += 1
                elif count == 1:
                    # Response to OUR CK0 — complete with CK2
                    send_ck2(pkt)
                    ck_count += 1
                    print(f"  Our CK exchange #{ck_count} complete")
                elif count == 2:
                    # Mac completed its CK exchange
                    ck_count += 1
                    print(f"  Mac CK exchange #{ck_count} complete")
        except socket.timeout:
            continue

    print(f"  Total CK exchanges: {ck_count}")

    # Send MIDI Note On
    ts = get_timestamp() & 0xFFFFFFFF
    midi = struct.pack('>BBHII', 0x80, 0x61, 0x1000, ts, SSRC)
    midi += bytes([0x03, 0x90, 0x3C, 0x64])
    print(f"\nSending MIDI Note On: {midi.hex()}")
    data.sendto(midi, data_addr)
    print("Sent! Check MIDI Monitor on the Cubase Mac.")

    # Keep alive, handle CK
    print("\nKeeping session alive (Ctrl+C to quit)...")
    while True:
        try:
            pkt, addr = data.recvfrom(1024)
            if len(pkt) >= 36 and pkt[2:4] == b'CK':
                count = pkt[8]
                if count == 0:
                    resp = build_ck_response(SSRC, 1, pkt, get_timestamp())
                    data.sendto(resp, addr)
            elif len(pkt) >= 12 and pkt[0] & 0xC0 == 0x80:
                print(f"  << RTP packet received ({len(pkt)} bytes): {pkt.hex()}")
        except socket.timeout:
            continue
        except KeyboardInterrupt:
            break

    cleanup()

if __name__ == "__main__":
    main()
