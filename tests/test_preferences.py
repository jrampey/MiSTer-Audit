"""Exercise preferences against a tiny hash-identified library, without real ROMs."""
import csv
import hashlib
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='mister-preferences-') as td:
    root = Path(td)
    scripts = root / 'Scripts'
    scripts.mkdir()
    games = root / 'games' / 'NES'
    games.mkdir(parents=True)
    (root / 'saves').mkdir()
    runtime = scripts / 'MiSTer_Audit.sh'
    runtime.write_text((repo / 'MiSTer_Audit.sh').read_text().replace('ROOT="/media/fat"', f'ROOT="{root}"'))
    ini = scripts / 'MiSTer_Audit.ini'
    rows = []
    for label, region, release in [('American', 'USA', 'Retail/Standard'), ('European', 'Europe', 'Retail/Standard'), ('Japanese', 'Japan', 'Retail/Standard'), ('Worldwide', 'World', 'Retail/Standard'), ('Virtual', 'Japan', 'Virtual Console')]:
        payload = label.encode()
        (games / f'{label}.nes').write_bytes(payload)
        name = f'{label} ({region})' + (' (Virtual Console)' if label == 'Virtual' else ' (Rev 1)')
        rows.append([hashlib.sha1(payload).hexdigest(), name, name + '.nes', 'Synthetic', len(payload), '0', '0', 'NES', 'NES', 'NES', region, release, 'Licensed'])
    with (scripts / 'mister_hash_database.tsv').open('w') as f:
        writer = csv.writer(f, delimiter='\t', lineterminator='\n')
        writer.writerow(['sha1','canonical_title','canonical_rom_name','dat_source','size','crc32','md5','mister_system','mister_core','expected_folder','region','release_type','license_status'])
        writer.writerows(rows)
        for i in range(1000):
            writer.writerow([hashlib.sha1(str(i).encode()).hexdigest(), f"Padding {i}", f"Padding {i}.sfc", "Synthetic", 1, "0", "0", "SNES", "SNES", "SNES", "USA", "Retail/Standard", "Licensed"])
    def run(command, inputs):
        return subprocess.run(['bash', str(runtime), command], input=inputs, text=True, capture_output=True, timeout=60)
    def audit(mode='1'):
        result = run('audit', mode)
        assert result.returncode == 0, result.stdout + result.stderr
        with (root / 'GameLibraryAudit/library_catalog.csv').open() as f:
            return {r['original_filename']: r for r in csv.DictReader(f)}
    result = audit('2')
    assert ini.exists(), 'INI not created on first launch'
    defaults = ini.read_text()
    assert result['American.nes']['curated_destination'] == 'NES'
    assert result['American.nes']['proposed_filename'] == 'American (Rev 1).nes'
    assert result['European.nes']['curated_destination'] == 'NES/!Europe'
    for region, label in [('Europe', 'European'), ('Japan', 'Japanese')]:
        ini.write_text(defaults.replace('PARENT_REGION=USA', f'PARENT_REGION={region}'))
        before = ini.read_text()
        blocked = run('update', '1')
        assert 'Preferences changed' in blocked.stdout, blocked.stdout
        result = audit()
        assert ini.read_text() == before, 'User preferences overwritten'
        assert result[f'{label}.nes']['curated_destination'] == 'NES'
        assert result[f'{label}.nes']['proposed_filename'] == f'{label} (Rev 1).nes'
        assert result['American.nes']['curated_destination'] == 'NES/!USA'
        assert result['Worldwide.nes']['curated_destination'] == 'NES/!World'
        assert result['Virtual.nes']['curated_destination'] == 'NES/!Virtual Console'
        bundle = (root / 'GameLibraryAudit/MiSTer_Library_Audit.txt').read_text()
        assert f'Regions: {region}' in bundle
        assert 'Hashes calculated this run: 0' in bundle, 'Region switch unnecessarily rehashed library'
    ini.write_text(defaults.replace('PARENT_REGION=USA','PARENT_REGION=Japan').replace('WORLD_IN_PARENT=0','WORLD_IN_PARENT=1').replace('STRIP_PARENT_REGION_TAG=1','STRIP_PARENT_REGION_TAG=0').replace('GROUP_SPECIAL_RELEASES=1','GROUP_SPECIAL_RELEASES=0'))
    result = audit()
    assert result['Worldwide.nes']['curated_destination'] == 'NES'
    assert result['Virtual.nes']['curated_destination'] == 'NES'
    assert result['Japanese.nes']['proposed_filename'] == 'Japanese (Japan) (Rev 1).nes'
    # Preview/apply consume the refreshed plan; explicit confirmation is still required.
    preview = run('update', '1\n\n')
    assert 'Audit compatibility check: PASS' in preview.stdout, preview.stdout
    applied = run('update', '2APPLY\n')
    assert 'Finished. Rollback manifest:' in applied.stdout, applied.stdout
    assert (games / 'Japanese (Japan) (Rev 1).nes').exists()
    assert (games / '!USA/American (USA) (Rev 1).nes').exists()
    ini.write_text('[organization]\r\nPARENT_REGION = EU ; alias\r\n')
    result = audit()
    assert any(r['curated_destination'] == 'NES' and 'European' in r['original_filename'] for r in result.values())
    for text in ['PARENT_REGION=Atlantis', 'WORLD_IN_PARENT=yes', 'PARENT_REGION=$(touch /tmp/mister-injection)', '[unexpected]\nPARENT_REGION=USA']:
        ini.write_text(text)
        result = run('audit','2')
        assert result.returncode != 0 and 'ERROR:' in result.stderr, result.stdout
    # Existing legacy completion policy migrates without discarding its values.
    ini.unlink()
    (scripts / 'AUDIT_POLICY.conf').write_text('COMPLETION_REGIONS=Japan\nCOMPLETION_INCLUDE_WORLD=0\n')
    audit()
    assert 'COMPLETION_REGIONS=Japan' in ini.read_text()
print('Preferences integration passed: defaults, migration, EU/JP, Fast cache, stale-plan blocking, flags, CRLF, invalid data.')
