"""Canonicalize the unsigned universal renderer without ignoring code bytes."""
import struct


def canonical_renderer(raw):
    data = bytearray(raw)
    magic, count = struct.unpack_from('>II', data)
    if magic != 0xcafebabe or count != 2:
        raise ValueError('Expected the universal launcher renderer')
    for index in range(count):
        _, _, start, size, _ = struct.unpack_from('>IIIII', data, 8 + index * 20)
        if start + size > len(data) or size < 32:
            raise ValueError('Invalid renderer slice')
        magic, = struct.unpack_from('<I', data, start)
        commands, command_bytes = struct.unpack_from('<II', data, start + 16)
        if magic != 0xfeedfacf or command_bytes > size - 32:
            raise ValueError('Invalid renderer header')
        cursor, end, found = start + 32, start + 32 + command_bytes, False
        for _ in range(commands):
            if cursor + 8 > end:
                raise ValueError('Invalid renderer command')
            command, length = struct.unpack_from('<II', data, cursor)
            if length < 8 or cursor + length > end:
                raise ValueError('Invalid renderer command size')
            if command == 0x19 and length >= 72 and data[cursor+8:cursor+24] == b'__LINKEDIT\0\0\0\0\0\0':
                # codesign expands this virtual size for a Developer ID signature
                # and does not shrink it again when removing that signature.
                # All other header, executable and data bytes remain verified.
                data[cursor+32:cursor+40] = bytes(8)
                found = True
            cursor += length
        if not found:
            raise ValueError('Missing renderer linkedit segment')
    return bytes(data)
