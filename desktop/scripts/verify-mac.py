"""Verify ad-hoc code/page/resource digests without relying on rcodesign's CMS verifier."""
import hashlib
import os
import plistlib
import struct
import sys
from pathlib import Path


def code_directories(data):
    magic = struct.unpack('>I', data[:4])[0]
    if magic in (0xCAFEBABE, 0xCAFEBABF):
        count = struct.unpack_from('>I', data, 4)[0]
        result = []
        for index in range(count):
            entry = struct.unpack_from('>IIQQII' if magic == 0xCAFEBABF else '>IIIII', data, 8 + index * (32 if magic == 0xCAFEBABF else 20))
            result.extend(code_directories(data[entry[2]:entry[2] + entry[3]]))
        return result
    if struct.unpack('<I', data[:4])[0] != 0xFEEDFACF:
        return []
    commands = struct.unpack_from('<I', data, 16)[0]
    cursor = 32
    offset = None
    for _ in range(commands):
        command, length = struct.unpack_from('<II', data, cursor)
        if command == 0x1D:
            offset, size = struct.unpack_from('<II', data, cursor + 8)
        cursor += length
    assert offset is not None, 'Mach-O sin firma'
    signature = data[offset:offset + size]
    assert struct.unpack_from('>I', signature)[0] == 0xFADE0CC0
    count = struct.unpack_from('>I', signature, 8)[0]
    blobs = {}
    for index in range(count):
        slot, start = struct.unpack_from('>II', signature, 12 + index * 8)
        length = struct.unpack_from('>I', signature, start + 4)[0]
        blobs[slot] = signature[start:start + length]
    result = []
    for slot, directory in blobs.items():
        if slot != 0:
            continue
        _, _, version, flags, hash_offset, _, special, pages, limit = struct.unpack_from('>9I', directory)
        hash_size, hash_type, _, page_exponent = struct.unpack_from('4B', directory, 36)
        digest = hashlib.sha256 if hash_type in (2, 3) else hashlib.sha1
        if version >= 0x20300 and not limit:
            limit = struct.unpack_from('>Q', directory, 56)[0]
        page_size = 1 << page_exponent
        assert flags & 2, 'Se esperaba firma ad hoc'
        for page in range(pages):
            raw = data[page * page_size:min((page + 1) * page_size, limit)]
            expected = directory[hash_offset + page * hash_size:hash_offset + (page + 1) * hash_size]
            assert digest(raw).digest()[:hash_size] == expected, f'Hash de código incorrecto: página {page}'
        for special_slot in (2, 5, 7):
            if special_slot in blobs and special_slot <= special:
                expected = directory[hash_offset - special_slot * hash_size:hash_offset - (special_slot - 1) * hash_size]
                assert digest(blobs[special_slot]).digest()[:hash_size] == expected, 'Sello de permisos/requisitos incorrecto'
        result.append({'cdhash': digest(directory).digest()[:20], 'directory': directory, 'digest': digest, 'hash_offset': hash_offset, 'hash_size': hash_size, 'special': special, 'blobs': blobs})
    assert result, 'Falta el CodeDirectory'
    return result


def verify(bundle):
    records = {}
    code_count = 0
    for file in bundle.rglob('*'):
        if file.is_symlink() or not file.is_file():
            continue
        with file.open('rb') as stream:
            magic = stream.read(4)
        if magic not in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
            continue
        values = code_directories(file.read_bytes())
        if values:
            records[file.resolve()] = values
            code_count += len(values)
    sealed = 0
    for resources in bundle.rglob('CodeResources'):
        if resources.is_symlink() or resources.parent.name != '_CodeSignature':
            continue
        base = resources.parent.parent
        plist = plistlib.loads(resources.read_bytes())
        for name, entry in plist.get('files2', {}).items():
            target = base / name
            if isinstance(entry, bytes):
                assert hashlib.sha1(target.read_bytes()).digest() == entry
                continue
            if 'symlink' in entry:
                assert target.is_symlink() and os.readlink(target) == entry['symlink'], f'Enlace inválido: {target}'
                continue
            if not target.exists() and entry.get('optional'):
                continue
            if 'hash2' in entry:
                assert hashlib.sha256(target.read_bytes()).digest() == entry['hash2'], f'Recurso modificado: {target}'
            if 'hash' in entry:
                assert hashlib.sha1(target.read_bytes()).digest() == entry['hash'], f'Recurso modificado: {target}'
            if 'cdhash' in entry:
                if target.is_file():
                    executable = target
                else:
                    info_file = target / ('Contents/Info.plist' if target.suffix == '.app' else 'Resources/Info.plist')
                    info = plistlib.loads(info_file.read_bytes())
                    executable = target / ('Contents/MacOS' if target.suffix == '.app' else '') / info['CFBundleExecutable']
                assert entry['cdhash'] in [record['cdhash'] for record in records[executable.resolve()]], f'Bundle anidado modificado: {target}'
            sealed += 1
        # Match the external bundle resources/plist to the main executable's signed slots.
        info_file = base / 'Info.plist'
        if not info_file.exists():
            info_file = base / 'Resources/Info.plist'
        info = plistlib.loads(info_file.read_bytes())
        executable = base / ('MacOS' if (base / 'MacOS').is_dir() else '') / info['CFBundleExecutable']
        for record in records[executable.resolve()]:
            for slot, file in ((1, info_file), (3, resources)):
                assert record['special'] >= slot
                start = record['hash_offset'] - slot * record['hash_size']
                expected = record['directory'][start:start + record['hash_size']]
                assert record['digest'](file.read_bytes()).digest()[:record['hash_size']] == expected, f'Sello del bundle inválido: {file}'
    assert (bundle / 'Contents/_CodeSignature/CodeResources').exists()
    assert code_count and sealed
    print(f'{bundle.parent.name}: {code_count} firmas de código y {sealed} recursos/enlaces anidados verificados')

if __name__ == '__main__':
    for argument in sys.argv[1:]:
        verify(Path(argument))
