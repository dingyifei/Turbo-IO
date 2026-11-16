"""Read Objective-C method type encodings from an arm64 Mach-O image, offline.

No device, no dyld: parses __objc_classlist / __objc_catlist and the class,
class_ro_t and method_list_t records (relative and pointer method lists,
chained-fixup or plain pointers). Used by test.py's host selector parity group.

methods(path) -> {(class_name, '+'|'-', selector): type_encoding}
"""
import struct

MH_MAGIC_64 = 0xfeedfacf
FAT_MAGIC = 0xcafebabe
CPU_TYPE_ARM64 = 0x0100000c
LC_SEGMENT_64 = 0x19


def _thin(data):
    if struct.unpack_from('>I', data, 0)[0] == FAT_MAGIC:
        count = struct.unpack_from('>I', data, 4)[0]
        for i in range(count):
            cpu, _sub, offset, size, _align = struct.unpack_from('>iiIII', data, 8 + 20 * i)
            if cpu == CPU_TYPE_ARM64:
                return data[offset:offset + size]
        raise ValueError('no arm64 slice')
    return data


class Image:
    def __init__(self, data):
        self.data = _thin(data)
        magic, cpu, _sub, _ftype, ncmds, _size = struct.unpack_from('<IiiIII', self.data, 0)
        if magic != MH_MAGIC_64 or cpu != CPU_TYPE_ARM64:
            raise ValueError('not a thin arm64 Mach-O')
        self.segments, self.sections = [], {}
        at = 32
        for _ in range(ncmds):
            cmd, size = struct.unpack_from('<II', self.data, at)
            if cmd == LC_SEGMENT_64:
                segname = self.data[at + 8:at + 24].rstrip(b'\0').decode()
                vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', self.data, at + 24)
                nsects = struct.unpack_from('<I', self.data, at + 64)[0]
                self.segments.append((vmaddr, vmsize, fileoff, filesize, segname))
                for s in range(nsects):
                    base = at + 72 + 80 * s
                    sectname = self.data[base:base + 16].rstrip(b'\0').decode()
                    addr, ssize, offset = struct.unpack_from('<QQI', self.data, base + 32)
                    self.sections[sectname] = (addr, ssize, offset)
            at += size
        self.base = min(s[0] for s in self.segments if s[4] != '__PAGEZERO')

    def off(self, vmaddr):
        for addr, size, fileoff, filesize, _name in self.segments:
            if addr <= vmaddr < addr + size:
                if vmaddr - addr >= filesize:
                    return None
                return fileoff + vmaddr - addr
        return None

    def ptr(self, vmaddr):
        """A pointer-sized slot: plain, or a chained-fixup rebase (bind -> None)."""
        o = self.off(vmaddr)
        if o is None:
            return None
        raw = struct.unpack_from('<Q', self.data, o)[0]
        if raw == 0:
            return 0
        if raw >> 63:  # bind: target outside this image
            return None
        if self.base <= raw < self.base + (1 << 36) and not (raw >> 36) & 0xfff00:
            return raw  # a plain pointer
        target = raw & ((1 << 36) - 1)
        high8 = (raw >> 36) & 0xff
        target |= high8 << 56
        if target < self.base:
            target += self.base  # DYLD_CHAINED_PTR_64_OFFSET
        return target

    def i32(self, vmaddr):
        o = self.off(vmaddr)
        return None if o is None else struct.unpack_from('<i', self.data, o)[0]

    def u32(self, vmaddr):
        o = self.off(vmaddr)
        return None if o is None else struct.unpack_from('<I', self.data, o)[0]

    def cstr(self, vmaddr):
        o = self.off(vmaddr)
        if o is None:
            return None
        end = self.data.index(b'\0', o)
        return self.data[o:end].decode('utf-8', 'replace')

    def method_list(self, vmaddr):
        out = {}
        if not vmaddr:
            return out
        flags_entsize, count = self.u32(vmaddr), self.u32(vmaddr + 4)
        if flags_entsize is None or count is None or count > 100000:
            return out
        relative = bool(flags_entsize & 0x80000000)
        entsize = flags_entsize & 0xfffc
        for i in range(count):
            e = vmaddr + 8 + i * entsize
            if relative:
                selref = e + self.i32(e)
                types = e + 4 + self.i32(e + 4)
                name_ptr = self.ptr(selref)
                name = self.cstr(name_ptr) if name_ptr else None
                if name is None:  # direct selector offsets (shared cache style)
                    name = self.cstr(selref)
                out[name] = self.cstr(types)
            else:
                name_ptr, types_ptr = self.ptr(e), self.ptr(e + 8)
                out[self.cstr(name_ptr)] = self.cstr(types_ptr)
        return out

    def class_record(self, cls):
        """(name, instance methods, metaclass address) of a class_t at cls."""
        data = self.ptr(cls + 32)
        if not data:
            return None
        ro = data & ~7
        name_ptr, methods = self.ptr(ro + 24), self.ptr(ro + 32)
        return self.cstr(name_ptr) if name_ptr else None, self.method_list(methods), self.ptr(cls)

    def methods(self):
        found = {}

        def add(name, sign, table):
            for sel, types in table.items():
                found[(name, sign, sel)] = types

        if '__objc_classlist' in self.sections:
            addr, size, _ = self.sections['__objc_classlist']
            for i in range(size // 8):
                cls = self.ptr(addr + 8 * i)
                rec = cls and self.class_record(cls)
                if not rec or not rec[0]:
                    continue
                name, inst, meta = rec
                add(name, '-', inst)
                mrec = meta and self.class_record(meta)
                if mrec:
                    add(name, '+', mrec[1])
        if '__objc_catlist' in self.sections:
            addr, size, _ = self.sections['__objc_catlist']
            for i in range(size // 8):
                cat = self.ptr(addr + 8 * i)
                if not cat:
                    continue
                cls = self.ptr(cat + 8)
                rec = cls and self.class_record(cls)
                if not rec or not rec[0]:
                    continue  # category on a class from another image
                add(rec[0], '-', self.method_list(self.ptr(cat + 16)))
                add(rec[0], '+', self.method_list(self.ptr(cat + 24)))
        return found


def demangle_class(name):
    """_TtC23rayneo_venus_sdk_plugin22AiResultListenerBridge -> rayneo_venus_sdk_plugin.AiResultListenerBridge"""
    if not name.startswith('_TtC'):
        return name
    rest, parts = name[4:], []
    while rest and rest[0].isdigit():
        n = 0
        while rest[0].isdigit():
            n, rest = n * 10 + int(rest[0]), rest[1:]
        parts.append(rest[:n])
        rest = rest[n:]
    return '.'.join(parts) if len(parts) >= 2 and not rest else name


def methods(path):
    with open(path, 'rb') as stream:
        image = Image(stream.read())
    return {(demangle_class(c), s, sel): t for (c, s, sel), t in image.methods().items()}


if __name__ == '__main__':
    import sys
    table = methods(sys.argv[1])
    want = sys.argv[2] if len(sys.argv) > 2 else None
    for (cls, sign, sel), types in sorted(table.items()):
        if want is None or want in cls:
            print(f'{sign}[{cls} {sel}] {types}')
