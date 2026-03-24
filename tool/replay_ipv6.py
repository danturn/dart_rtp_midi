#!/usr/bin/env python3
"""Send an RTP-MIDI Note On over IPv6 link-local (like Apple does)."""

import socket
import struct
import time
import sys

# Cubase Mac's link-local IPv6
REMOTE = "fe80::14bd:9902:492a:f2a3"
SCOPE_ID = 14  # en0 interface index
CONTROL_PORT = 5004
DATA_PORT = 5005

SSRC = 0xAABBCCDD
TOKEN = 0x12345678

def build_in(token, ssrc, name):
    name_bytes = name.encode() + b'\x00'
    return struct.pack('>HHIII', 0xFFFF, 0x494E, 2, token, ssrc) + name_bytes

def build_ck0(ssrc, t1):
    return struct.pack('>HHIB3x', 0xFFFF, 0x434B, ssrc, 0) + \
           struct.pack('>Q', t1) + b'\x00' * 16

def build_ck2(ssrc, ck1_data, t3):
    pkt = bytearray(36)
    struct.pack_into('>HHI', pkt, 0, 0xFFFF, 0x434B, ssrc)
    pkt[8] = 2
    pkt[12:28] = ck1_data[12:28]  # copy t1 and t2
    t3_hi = (t3 >> 32) & 0xFFFFFFFF
    t3_lo = t3 & 0xFFFFFFFF
    struct.pack_into('>II', pkt, 28, t3_hi, t3_lo)
    return bytes(pkt)

def build_bye(ssrc):
    return struct.pack('>HHIII', 0xFFFF, 0x4259, 2, 0, ssrc)

def make_addr(ip, port, scope):
    return (ip, port, 0, scope)

def main():
    scope = int(sys.argv[1]) if len(sys.argv) > 1 else SCOPE_ID

    # Bind to port 5004/5005 (matching Apple's convention exactly).
    ctrl = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
    ctrl.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    ctrl.bind(('::', CONTROL_PORT))
    data = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
    data.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    data.bind(('::', DATA_PORT))

    print(f"Local ports: {ctrl.getsockname()[1]}/{data.getsockname()[1]}")

    # 1. Control IN
    print("1. Control IN...")
    ctrl.sendto(build_in(TOKEN, SSRC, "Python Test"), make_addr(REMOTE, CONTROL_PORT, scope))
    resp, _ = ctrl.recvfrom(1024)
    print(f"   << {resp.hex()}")
    assert resp[2:4] == b'OK', "Expected OK"
    print("   Got control OK")

    # 2. Data IN
    print("2. Data IN...")
    data.sendto(build_in(TOKEN, SSRC, "Python Test"), make_addr(REMOTE, DATA_PORT, scope))
    resp, _ = data.recvfrom(1024)
    print(f"   << {resp.hex()}")
    assert resp[2:4] == b'OK', "Expected OK"
    print("   Got data OK")

    # 3. CK0
    print("3. CK0...")
    t1 = int(time.time() * 10000)  # 100us ticks
    data.sendto(build_ck0(SSRC, t1), make_addr(REMOTE, DATA_PORT, scope))
    ck1, _ = data.recvfrom(1024)
    print(f"   << CK1 ({len(ck1)}b)")

    # 4. CK2
    print("4. CK2...")
    t3 = int(time.time() * 10000)
    data.sendto(build_ck2(SSRC, ck1, t3), make_addr(REMOTE, DATA_PORT, scope))

    print("Session established. Waiting 5s...")
    time.sleep(5)

    # 5. MIDI Note On
    ts = int(time.time() * 10000) & 0xFFFFFFFF
    midi = struct.pack('>BBHII', 0x80, 0x61, 0x1000, ts, SSRC)
    midi += bytes([0x03, 0x90, 0x3C, 0x64])
    print(f"5. Sending MIDI: {midi.hex()}")
    data.sendto(midi, make_addr(REMOTE, DATA_PORT, scope))

    print("Waiting 10s...")
    time.sleep(10)

    # 6. BYE
    print("6. BYE")
    ctrl.sendto(build_bye(SSRC), make_addr(REMOTE, CONTROL_PORT, scope))
    data.sendto(build_bye(SSRC), make_addr(REMOTE, DATA_PORT, scope))

    ctrl.close()
    data.close()
    print("Done.")

if __name__ == "__main__":
    main()
