#!/usr/bin/env python3
"""Flash shared objects (.sol, AMF0): `sol.py dump FILE...` prints them, `sol.py write FILE NAME key=value...` writes one
(value: true/false, a number, or text)."""
import struct, sys

def read_value(b, o):
    t = b[o]; o += 1
    if t == 0: return struct.unpack('>d', b[o:o + 8])[0], o + 8
    if t == 1: return bool(b[o]), o + 1
    if t == 2: n = struct.unpack('>H', b[o:o + 2])[0]; return b[o + 2:o + 2 + n].decode('utf8', 'replace'), o + 2 + n
    if t in (3, 8):
        if t == 8: o += 4
        d = {}
        while True:
            n = struct.unpack('>H', b[o:o + 2])[0]; o += 2
            if n == 0 and b[o] == 9: return d, o + 1
            k = b[o:o + n].decode('utf8', 'replace'); o += n
            d[k], o = read_value(b, o)
    if t in (5, 6): return None, o
    if t == 10:
        n = struct.unpack('>I', b[o:o + 4])[0]; o += 4; a = []
        for _ in range(n):
            v, o = read_value(b, o); a.append(v)
        return a, o
    if t == 11: return ('date', struct.unpack('>d', b[o:o + 8])[0]), o + 10
    raise ValueError('AMF0 type %d' % t)

def dump(path):
    b = open(path, 'rb').read()
    o = 16; n = struct.unpack('>H', b[o:o + 2])[0]; name = b[o + 2:o + 2 + n].decode(); o += 2 + n + 4
    out = {}
    while o + 2 < len(b):
        n = struct.unpack('>H', b[o:o + 2])[0]; k = b[o + 2:o + 2 + n].decode('utf8', 'replace'); o += 2 + n
        out[k], o = read_value(b, o); o += 1
    return name, out

def amf(v):
    if isinstance(v, bool): return b'\x01' + (b'\x01' if v else b'\x00')
    if isinstance(v, (int, float)): return b'\x00' + struct.pack('>d', float(v))
    s = str(v).encode('utf8'); return b'\x02' + struct.pack('>H', len(s)) + s

def write(path, name, pairs):
    body = b'TCSO' + b'\x00\x04\x00\x00\x00\x00' + struct.pack('>H', len(name)) + name.encode() + b'\x00\x00\x00\x00'
    for k, v in pairs:
        body += struct.pack('>H', len(k)) + k.encode() + amf(v) + b'\x00'
    open(path, 'wb').write(b'\x00\xbf' + struct.pack('>I', len(body)) + body)

def parse(text):
    if text in ('true', 'false'): return text == 'true'
    try: return float(text)
    except ValueError: return text

if __name__ == '__main__':
    if sys.argv[1] == 'dump':
        for f in sys.argv[2:]:
            try: print(f, *dump(f))
            except Exception as e: print(f, 'illisible :', e)
    elif sys.argv[1] == 'write':
        write(sys.argv[2], sys.argv[3], [(kv.split('=', 1)[0], parse(kv.split('=', 1)[1])) for kv in sys.argv[4:]])
