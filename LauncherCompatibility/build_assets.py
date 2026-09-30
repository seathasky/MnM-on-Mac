"""Build the versioned assets embedded in the Xcode app. No network access.

Requires LLVM-MinGW and pristine Sikarugir 10.0_6 USER32/OLE32 inputs.
Generated output is kept beside the Xcode project, not the installed runtime.
"""
from pathlib import Path
import argparse,hashlib,json,shutil,struct,subprocess,sys,tempfile
from retina_integrity import canonical_renderer
p=argparse.ArgumentParser()
p.add_argument('--compiler',required=True,type=Path)
p.add_argument('--user32',required=True,type=Path)
p.add_argument('--ole32',required=True,type=Path)
a=p.parse_args()
root=Path(__file__).resolve().parent
output=root.parent/'LauncherCompatibilityAssets'
output.mkdir(exist_ok=True)
native_output=root.parent/'LauncherNativeAssets'
native_output.mkdir(exist_ok=True)
# Migrate the generated native asset out of the unsigned resource folder.
if (output/'MnMLauncherRetina.dylib').exists():
    shutil.move(str(output/'MnMLauncherRetina.dylib'),str(native_output/'MnMLauncherRetina.dylib'))
with tempfile.TemporaryDirectory(prefix='mnm-compat-build-') as temporary:
    stage=Path(temporary)
    subprocess.run([str(a.compiler),'-shared','-O2',str(root/'webview_bridge.c'),'-o',str(stage/'MnMWebViewBridge.dll'),'-luser32','-lgdi32'],check=True)
    subprocess.run([str(a.compiler),'-municode','-mwindows','-O2',str(root/'windows_launcher.c'),'-o',str(stage/'MnMWindowsLauncher.exe'),'-luser32'],check=True)
    subprocess.run(['xcrun','clang','-dynamiclib','-O2','-arch','x86_64','-arch','arm64','-mmacosx-version-min=14.0',str(root/'launcher_retina.m'),'-framework','Foundation','-o',str(stage/'MnMLauncherRetina.dylib')],check=True)
    subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(stage/'MnMLauncherRetina.dylib')],check=True)
    helper=(stage/'MnMWindowsLauncher.exe').read_bytes()
    pe=struct.unpack_from('<I',helper,60)[0]
    if struct.unpack_from('<H',helper,pe+24+68)[0]!=2:
        raise RuntimeError('Launcher helper must use the GUI subsystem, never a console.')
    for name,source,script in [('user32.dll',a.user32,'backport_user32.py'),('ole32.dll',a.ole32,'backport_ole32.py')]:
        destination=stage/name
        shutil.copyfile(source,destination)
        subprocess.run([sys.executable,str(root/script),str(destination)],check=True)
    hashes={}
    for name in ['MnMWebViewBridge.dll','MnMWindowsLauncher.exe','user32.dll','ole32.dll','MnMLauncherRetina.dylib']:
        shutil.copyfile(stage/name,(native_output if name=='MnMLauncherRetina.dylib' else output)/name)
        hashed=stage/name
        if name=='MnMLauncherRetina.dylib':
            # Developer ID signing changes the signature, not the renderer code.
            # Hash the canonical unsigned copy so distribution signing is safe.
            hashed=stage/'retina-unsigned.dylib'
            shutil.copyfile(stage/name,hashed)
            subprocess.run(['/usr/bin/codesign','--remove-signature',str(hashed)],check=True)
        content=hashed.read_bytes()
        if name=='MnMLauncherRetina.dylib':
            content=canonical_renderer(content)
        hashes[name]=hashlib.sha256(content).hexdigest()
    (output/'manifest.json').write_text(json.dumps({'version':'mnm-webview2-1','wine':'Sikarugir 10.0_6','files':hashes},indent=2)+'\n')
print('Built compatibility assets:',output)
