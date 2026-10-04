#!/usr/bin/env python3
"""Export reviewable GameBridge sources without local/user runtime state."""
import hashlib, json, pathlib, re, shutil, subprocess, sys, zipfile
root = pathlib.Path(__file__).resolve().parents[1]
output = root / 'build/public-source/GameBridge'
if output.exists():
    raise SystemExit('Export destination exists; retain or move it before rebuilding.')
tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
files = set(p for p in tracked if p and not p.startswith(('docs/', 'Libraries/', '.github/', 'images/')))
files.discard('README.md')
files.add('docs/release/README-public.md')
for base in ['WhiskyKit/Sources/WhiskyKit/GameBridge', 'WhiskyKit/Tests/WhiskyKitTests']:
    files.update(str(p.relative_to(root)) for p in (root/base).glob('*.swift'))
files.update(['scripts/package-bootstrap.py', 'scripts/test-bootstrap-packaging.py', 'scripts/embed-bootstrap.sh', 'scripts/export-public-source.py'])
files.update(str(p.relative_to(root)) for p in (root/'scripts/compatibility').rglob('*') if p.is_file() and p.name not in ['ptrshim-source.json', 'ptrshim-deskrawl.patch', 'README.md'] and '__pycache__' not in p.parts)
secret = re.compile(rb'(?:7656119[0-9]{10}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)')
manifest = {}
for name in sorted(files):
    p = root/name
    if p.is_symlink() or not p.is_file(): raise SystemExit('Unsafe input: '+name)
    if any(x.lower() in {'prefix','steamapps','htmlcache','userdata','config.vdf','loginusers.vdf'} for x in pathlib.Path(name).parts): raise SystemExit('Private path: '+name)
    data = p.read_bytes()
    if secret.search(data): raise SystemExit('Potential account/token data: '+name)
    q = output/name; q.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(p,q)
    manifest[name] = hashlib.sha256(data).hexdigest()
for source,target in [('docs/release/README-public.md','README.md'),('docs/release/STATUS.md','docs/release/STATUS.md')]:
    q=output/target;q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/source,q)
    manifest[target]=hashlib.sha256(q.read_bytes()).hexdigest()
(output/'SOURCE-INVENTORY.json').write_text(json.dumps({'schema':1,'upstream':'https://github.com/Whisky-App/Whisky','baseline':'fd5480a76b3ebfe3419a1ab86ca3695f5cc328f8','files':manifest},indent=2)+'\n')
archive=output.parent/'GameBridge-public-source.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(output.rglob('*')):
        if p.is_file():z.write(p,'GameBridge/'+str(p.relative_to(output)))
print(json.dumps({'files':len(manifest),'directory':str(output),'archive':str(archive),'bytes':archive.stat().st_size}))
