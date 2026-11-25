"""Create the installable KOReader ZIP from the release files."""
from pathlib import Path
import re
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

root = Path(__file__).resolve().parents[1]
plugin = root / 'versoink.koplugin'
version = re.search(r'version\s*=\s*"([0-9.]+)"', (plugin / '_meta.lua').read_text()).group(1)
output = root / 'dist' / f'toumo-v{version}.zip'
output.parent.mkdir(exist_ok=True)
files = ['_meta.lua', 'main.lua', 'versoink_job.lua', 'versoink_raster.lua',
         'paper.grain', 'versoink.c', 'versoink-armel.so', 'README.txt']

with ZipFile(output, 'w') as archive:
    for source in [plugin / name for name in files] + [root / 'LICENSE']:
        info = ZipInfo(f'{plugin.name}/{source.name}', (1980, 1, 1, 0, 0, 0))
        info.create_system = 3
        mode = 0o755 if source.suffix == '.so' else 0o644
        info.external_attr = (0o100000 | mode) << 16
        archive.writestr(info, source.read_bytes(), compress_type=ZIP_DEFLATED, compresslevel=8)

with ZipFile(output) as archive:
    assert archive.testzip() is None
print(output)
