"""Minimal client for the VICE binary monitor (VICE 3.5 and later).

Protocol from the VICE manual, chapter "Binary Monitor": requests are
STX, API version, body length (4), request id (4), command, body;
responses are STX, API version, body length (4), response type, error
code, request id (4), body. Events (stopped, resumed, checkpoint hit)
arrive with request id 0xFFFFFFFF.
"""
import socket
import struct
import time

STX = 0x02
API = 0x02
EVENT_ID = 0xFFFFFFFF

CMD_MEM_GET = 0x01
CMD_MEM_SET = 0x02
CMD_CHECKPOINT_SET = 0x12
CMD_CHECKPOINT_DELETE = 0x13
CMD_REGS_GET = 0x31
CMD_REGS_SET = 0x32
CMD_DUMP = 0x41
CMD_UNDUMP = 0x42
CMD_BANKS = 0x82
CMD_REGS_AVAILABLE = 0x83
CMD_EXIT = 0xAA
CMD_QUIT = 0xBB
CMD_PING = 0x81

RESP_CHECKPOINT = 0x11
RESP_STOPPED = 0x62
RESP_RESUMED = 0x63

OP_EXEC = 0x04


class ViceError(Exception):
    pass


class Vice:
    def __init__(self, host="127.0.0.1", port=6502, timeout=60):
        deadline = time.time() + timeout
        while True:
            try:
                self.sock = socket.create_connection((host, port), timeout=5)
                break
            except OSError:
                if time.time() > deadline:
                    raise
                time.sleep(0.5)
        self.sock.settimeout(timeout)
        self.next_id = 1
        self.events = []
        self.regs = {}
        self.banks = {}
        self.ping()
        for rid, size, name in self._regs_available():
            self.regs[name] = rid
        self.banks = dict((n, i) for i, n in self._banks())

    # --- transport -----------------------------------------------------
    def _recv(self, n):
        data = b""
        while len(data) < n:
            chunk = self.sock.recv(n - len(data))
            if not chunk:
                raise ViceError("connection closed")
            data += chunk
        return data

    def _read_response(self):
        head = self._recv(12)
        stx, api, length, rtype, err, rid = struct.unpack("<BBIBBI", head)
        if stx != STX:
            raise ViceError("bad response start %02x" % stx)
        return rtype, err, rid, self._recv(length)

    def request(self, cmd, body=b""):
        rid = self.next_id
        self.next_id += 1
        self.sock.sendall(struct.pack("<BBII", STX, API, len(body), rid)
                          + bytes([cmd]) + body)
        while True:
            rtype, err, got, data = self._read_response()
            if got == EVENT_ID or got != rid:
                self.events.append((rtype, data))
                continue
            if err:
                raise ViceError("command %02x failed: error %02x" % (cmd, err))
            return rtype, data

    def wait_event(self, rtype, timeout=60):
        """Wait for an event of rtype (e.g. RESP_CHECKPOINT); returns its body."""
        for i, (t, d) in enumerate(self.events):
            if t == rtype:
                del self.events[i]
                return d
        self.sock.settimeout(timeout)
        while True:
            t, err, rid, d = self._read_response()
            if t == rtype:
                return d
            self.events.append((t, d))

    # --- commands --------------------------------------------------------
    def ping(self):
        self.request(CMD_PING)

    def _regs_available(self):
        _, data = self.request(CMD_REGS_AVAILABLE, bytes([0]))
        count = struct.unpack_from("<H", data)[0]
        pos, out = 2, []
        for _ in range(count):
            size = data[pos]
            rid, bits, nlen = data[pos + 1], data[pos + 2], data[pos + 3]
            name = data[pos + 4:pos + 4 + nlen].decode()
            out.append((rid, bits, name))
            pos += size + 1
        return out

    def _banks(self):
        _, data = self.request(CMD_BANKS)
        count = struct.unpack_from("<H", data)[0]
        pos, out = 2, []
        for _ in range(count):
            size = data[pos]
            bid = struct.unpack_from("<H", data, pos + 1)[0]
            nlen = data[pos + 3]
            out.append((bid, data[pos + 4:pos + 4 + nlen].decode()))
            pos += size + 1
        return out

    def mem_get(self, start, end, bank="ram"):
        body = struct.pack("<BHHBH", 0, start, end, 0, self.banks[bank])
        _, data = self.request(CMD_MEM_GET, body)
        length = struct.unpack_from("<H", data)[0]
        return data[2:2 + length]

    def mem_set(self, start, data, bank="ram"):
        body = struct.pack("<BHHBH", 0, start, start + len(data) - 1, 0,
                           self.banks[bank]) + bytes(data)
        self.request(CMD_MEM_SET, body)

    def regs_get(self):
        _, data = self.request(CMD_REGS_GET, bytes([0]))
        count = struct.unpack_from("<H", data)[0]
        pos, out = 2, {}
        names = dict((v, k) for k, v in self.regs.items())
        for _ in range(count):
            size = data[pos]
            rid = data[pos + 1]
            value = struct.unpack_from("<H", data, pos + 2)[0]
            out[names.get(rid, rid)] = value
            pos += size + 1
        return out

    def regs_set(self, values):
        items = b"".join(struct.pack("<BBH", 3, self.regs[k], v)
                         for k, v in values.items())
        self.request(CMD_REGS_SET, bytes([0]) + struct.pack("<H", len(values)) + items)

    def checkpoint(self, addr, temporary=True):
        body = struct.pack("<HHBBBB", addr, addr, 1, 1, OP_EXEC, 1 if temporary else 0)
        _, data = self.request(CMD_CHECKPOINT_SET, body)
        return struct.unpack_from("<I", data)[0]

    def delete_checkpoint(self, cid):
        try:
            self.request(CMD_CHECKPOINT_DELETE, struct.pack("<I", cid))
        except ViceError:
            pass                                # already gone (temporary, hit)

    def dump(self, path, disks=False):
        """Snapshot; disks=True also stores the attached disk images (and
        the drives' state that goes with them)."""
        name = path.encode()
        self.request(CMD_DUMP, bytes([0, 1 if disks else 0, len(name)]) + name)

    def undump(self, path):
        name = path.encode()
        self.request(CMD_UNDUMP, bytes([len(name)]) + name)

    def resume(self):
        self.request(CMD_EXIT)

    def quit(self):
        try:
            self.request(CMD_QUIT)
        except (ViceError, OSError):
            pass
        self.sock.close()
