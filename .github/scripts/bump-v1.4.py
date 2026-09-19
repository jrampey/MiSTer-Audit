from pathlib import Path

files = [
    Path('MiSTer_Audit.sh'),
    Path('MiSTer_Audit.sh'),
    Path('README.md'),
    Path('PROJECT_CONTEXT.md'),
]
files += sorted(Path('wiki').glob('*.md'))
files += sorted(Path('tests').glob('*.sh'))
files += sorted(Path('.github/workflows').glob('*.yml'))

for p in files:
    if not p.is_file():
        continue
    s = p.read_text()
    original = s
    s = s.replace('v1.3', 'v1.4')
    s = s.replace('EXPECTED_EXPORTER_VERSION="1.3"', 'EXPECTED_EXPORTER_VERSION="1.4"')
    s = s.replace('EXPORTER_VERSION=1.3', 'EXPORTER_VERSION=1.4')
    s = s.replace('exporter_version=1.3', 'exporter_version=1.4')
    if p.name == 'README.md' and '> **Current release: v1.4**' in s:
        marker = '> **Current release: v1.4**\n'
        note = '\n> **v1.4:** adds configurable audit policy, including safe multi-region completion policy loading, while preserving the existing read-only audit and updater safety model.\n'
        if note.strip() not in s:
            s = s.replace(marker, marker + note, 1)
    if p.name == 'PROJECT_CONTEXT.md' and 'The current release is **v1.4**.' in s:
        marker = 'The current release is **v1.4**. Do not increment the release version unless explicitly instructed.\n'
        note = '\nv1.4 adds `AUDIT_POLICY.conf` as a non-executable, whitelist-parsed user policy layer. Default policy preserves prior USA + World-compatible retail completion behavior; comma-separated completion regions are supported.\n'
        if note.strip() not in s:
            s = s.replace(marker, marker + note, 1)
    if s != original:
        p.write_text(s)
