"""Boot a disposable ARM Linux guest and exercise the KOReader release's LuaJIT and CRe."""
import argparse
import gzip
from pathlib import Path
import shutil
import subprocess
import tempfile
from zipfile import ZipFile


def build_overlay(root, args):
    project = Path(__file__).resolve().parents[1]
    ko = root / 'ko'
    ko.mkdir()
    prefixes = ('ffi/', 'libs/', 'data/hyph/')
    files = {'luajit', 'setupkoenv.lua', 'data/epub.css', 'frontend/logger.lua', 'frontend/ui/time.lua',
             'fonts/noto/NotoSerif-Regular.ttf', 'fonts/noto/NotoSansCJKsc-Regular.otf'}
    with ZipFile(args.koreader_zip) as archive:
        for info in archive.infolist():
            if not info.filename.startswith('koreader/') or info.is_dir():
                continue
            name = info.filename[len('koreader/'):]
            if name not in files and not name.startswith(prefixes):
                continue
            if Path(name).is_absolute() or '..' in Path(name).parts:
                raise ValueError(f'Unexpected archive path: {name}')
            path = ko / name
            path.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info) as src, path.open('wb') as dst:
                shutil.copyfileobj(src, dst)
    (ko / 'luajit').chmod(0o755)
    with ZipFile(args.plugin_zip) as archive:
        for info in archive.infolist():
            parts = Path(info.filename).parts
            if info.is_dir():
                continue
            if len(parts) != 2 or parts[0] != 'toumo.koplugin' or parts[1] == '..':
                raise ValueError(f'Unexpected plugin path: {info.filename}')
            path = ko / info.filename
            path.parent.mkdir(exist_ok=True)
            with archive.open(info) as src, path.open('wb') as dst:
                shutil.copyfileobj(src, dst)
    (ko / 'fallback').mkdir()
    for name in ('toumo_raster.lua', 'paper.grain'):
        shutil.copy2(ko / 'toumo.koplugin' / name, ko / 'fallback' / name)
    shutil.copytree(ko / 'fallback', ko / 'generic-only')
    shutil.copy2(ko / 'toumo.koplugin' / 'toumo-armel-generic.so', ko / 'generic-only')
    for name in ('raster-abi.lua', 'fixture.epub'):
        shutil.copy2(project / 'tests' / name, ko / name)
    if args.armel_libs:
        (root / 'lib').mkdir()
        (root / 'armel').mkdir()
        for lib in args.armel_libs.glob('*.so*'):
            if lib.is_file():
                shutil.copy2(lib, root / 'armel' / lib.name)
        shutil.copy2(args.armel_libs / 'ld-linux.so.3', root / 'lib' / 'ld-linux.so.3')
    init = root / 'toumo-init'
    init.write_text('''#!/bin/sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev
ulimit -c 0
uname -mrs
cd /ko
LD_LIBRARY_PATH=/ko/libs:/armel ./luajit raster-abi.lua /ko/toumo.koplugin /ko/fallback /ko/fixture.epub /ko/generic-only
echo "TOUMO_EXIT=$?"
poweroff -f
''')
    init.chmod(0o755)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('arch', choices=('arm', 'aarch64'), help='QEMU guest CPU architecture')
    parser.add_argument('koreader_zip', type=Path, help='KOReader release ZIP for the target')
    parser.add_argument('plugin_zip', type=Path, help='installable Toumo ZIP to verify')
    parser.add_argument('kernel', type=Path, help='ARM Linux kernel for QEMU virt')
    parser.add_argument('initrd', type=Path, help='Linux initramfs with a shell, mount, poweroff and the matching libc')
    parser.add_argument('--armel-libs', type=Path, help='soft-float Linux runtime if the ARM guest only supplies hard-float')
    parser.add_argument('--no-neon', action='store_true', help='disable NEON; the KOReader runtime must itself run without NEON')
    parser.add_argument('--expect-library', help='assert which native library LuaJIT selected')
    args = parser.parse_args()
    if args.no_neon and args.arch != 'arm':
        parser.error('--no-neon requires an ARM32 guest')
    with tempfile.TemporaryDirectory() as temp:
        workspace = Path(temp)
        root = workspace / 'overlay'
        root.mkdir()
        build_overlay(root, args)
        cpio = workspace / 'overlay.cpio'
        names = [b'.', *(str(p.relative_to(root)).encode() for p in sorted(root.rglob('*')))]
        with cpio.open('wb') as out:
            subprocess.run(['cpio', '-o', '-H', 'newc', '-0'], input=b'\0'.join(names)+b'\0',
                           cwd=root, stdout=out, check=True)
        ramdisk = workspace / 'initrd.gz'
        with args.initrd.open('rb') as src, ramdisk.open('wb') as out:
            shutil.copyfileobj(src, out)
            with gzip.GzipFile(fileobj=out, mode='wb', compresslevel=1) as gz, cpio.open('rb') as src_cpio:
                shutil.copyfileobj(src_cpio, gz)
        cpu = 'cortex-a53' if args.arch == 'aarch64' else 'cortex-a15'
        if args.no_neon:
            cpu += ',neon=off,vfp-d32=off'
        result = subprocess.run([f'qemu-system-{args.arch}', '-M', 'virt', '-cpu', cpu, '-smp', '2',
                                 '-m', '1024M', '-nic', 'none', '-display', 'none', '-monitor', 'none',
                                 '-serial', 'stdio', '-no-reboot', '-kernel', args.kernel, '-initrd', ramdisk,
                                 '-append', 'console=ttyAMA0 quiet rdinit=/toumo-init panic=1'],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        log = result.stdout.decode(errors='replace')
        print(log, flush=True)
        result.check_returncode()
        if args.expect_library and ('TOUMO_NATIVE_LIB\t' + args.expect_library) not in log.splitlines():
            raise SystemExit(f'Expected the guest to use {args.expect_library}')
        if 'TOUMO_RASTER_PASS' not in log or 'TOUMO_EXIT=0' not in log.splitlines():
            raise SystemExit(1)


if __name__ == '__main__':
    main()
