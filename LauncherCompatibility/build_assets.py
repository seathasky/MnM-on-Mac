"""Build the versioned assets embedded in the Xcode app. No network access.

Requires LLVM-MinGW and pristine Sikarugir 10.0_6 USER32/OLE32 inputs.
Generated output is kept beside the Xcode project, not the installed runtime.
"""
from pathlib import Path
import argparse,hashlib,json,shutil,struct,subprocess,sys,tempfile
p=argparse.ArgumentParser()
p.add_argument('--compiler',required=True,type=Path)
p.add_argument('--user32',required=True,type=Path)
p.add_argument('--ole32',required=True,type=Path)
a=p.parse_args()
root=Path(__file__).resolve().parent
output=root.parent/'LauncherCompatibilityAssets'
output.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='mnm-compat-build-') as temporary:
    stage=Path(temporary)
    subprocess.run([str(a.compiler),'-shared','-O2',str(root/'webview_bridge.c'),'-o',str(stage/'MnMWebViewBridge.dll'),'-luser32','-lgdi32'],check=True)
    subprocess.run([str(a.compiler),'-municode','-mwindows','-O2',str(root/'windows_launcher.c'),'-o',str(stage/'MnMWindowsLauncher.exe'),'-luser32'],check=True)
    helper=(stage/'MnMWindowsLauncher.exe').read_bytes()
    pe=struct.unpack_from('<I',helper,60)[0]
    if struct.unpack_from('<H',helper,pe+24+68)[0]!=2:
        raise RuntimeError('Launcher helper must use the GUI subsystem, never a console.')
    for name,source,script in [('user32.dll',a.user32,'backport_user32.py'),('ole32.dll',a.ole32,'backport_ole32.py')]:
        destination=stage/name
        shutil.copyfile(source,destination)
        subprocess.run([sys.executable,str(root/script),str(destination)],check=True)
    hashes={}
    for name in ['MnMWebViewBridge.dll','MnMWindowsLauncher.exe','user32.dll','ole32.dll']:
        shutil.copyfile(stage/name,output/name)
        hashes[name]=hashlib.sha256((stage/name).read_bytes()).hexdigest()
    (output/'manifest.json').write_text(json.dumps({'version':'mnm-webview2-1','wine':'Sikarugir 10.0_6','files':hashes},indent=2)+'\n')
print('Built compatibility assets:',output)
