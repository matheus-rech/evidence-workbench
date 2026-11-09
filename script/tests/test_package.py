import pathlib, shutil, subprocess, tempfile, unittest, zipfile
SCRIPT = pathlib.Path(__file__).resolve().parents[1] / 'package.py'
class PackagingTests(unittest.TestCase):
    def test_archive_allowlist_and_symlink_parent(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp) / 'project'; root.mkdir()
            subprocess.run(['git','init','-q',str(root)],check=True)
            for name in ['Sources/a.swift','README.md','.codex/private.txt','ValidationSources/protocol.txt','.env.local']:
                p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('synthetic')
            subprocess.run(['git','-C',str(root),'add','Sources/a.swift','README.md','.codex/private.txt','ValidationSources/protocol.txt','.env.local'],check=True)
            app=root/'dist/EvidenceWorkbenchReview.app/Contents/MacOS';app.mkdir(parents=True);(app/'EvidenceWorkbenchReview').write_text('synthetic binary');(app/'EvidenceWorkbenchReview').chmod(0o755)
            (root/'script').mkdir();shutil.copy2(SCRIPT,root/'script/package.py')
            subprocess.run(['python3',str(root/'script/package.py')],check=True,capture_output=True)
            archive=root.parent/'EvidenceWorkbenchReview_macOS.zip'
            self.assertTrue(archive.is_file())
            with zipfile.ZipFile(archive) as z:
                self.assertIsNone(z.testzip());names=z.namelist()
                self.assertTrue(any(n.endswith('Sources/a.swift') for n in names))
                self.assertFalse(any(any(x in n for x in ['.codex','.env','ValidationSources']) for n in names))
                binary=next(n for n in names if n.endswith('/MacOS/EvidenceWorkbenchReview'))
                self.assertTrue((z.getinfo(binary).external_attr >> 16) & 0o111, 'App executable permission must survive ZIP extraction')
    def test_bundle_symlink_is_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            root=pathlib.Path(temp)/'project';root.mkdir();(root/'script').mkdir();shutil.copy2(SCRIPT,root/'script/package.py')
            subprocess.run(['git','init','-q',str(root)],check=True)
            outside=pathlib.Path(temp)/'private';outside.mkdir();(root/'dist').mkdir();(root/'dist/EvidenceWorkbenchReview.app').symlink_to(outside,target_is_directory=True)
            result=subprocess.run(['python3',str(root/'script/package.py')],capture_output=True)
            self.assertNotEqual(result.returncode,0)
            self.assertFalse((root.parent/'EvidenceWorkbenchReview_macOS.zip').exists())
if __name__ == '__main__': unittest.main()
