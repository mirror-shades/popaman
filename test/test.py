import os
import shutil
import time
import asyncio
from pathlib import Path
import sys
import tempfile
import json
import argparse

class AssetTracker:
    def __init__(self):
        # Directories
        self.directories = {
            'popaman_bin': None,  # Directory containing popaman executables
            'test_package_dir': None,  # Directory containing test packages
            'archives_dir': None,  # Directory containing archives
        }
        
        # Files
        self.files = {
            'popaman_exe': None,  # Main popaman executable
            'install_popaman_exe': None,  # Installer executable
            'test_package': None,  # Test package executable
            'archives': {  # Dictionary of archive files
                '7z': None,
                'zip': None,
            }
        }
    
    def set_directory(self, key, path):
        if key not in self.directories:
            raise KeyError(f"Unknown directory key: {key}")
        self.directories[key] = Path(path)
    
    def set_file(self, key, path):
        if key not in self.files:
            raise KeyError(f"Unknown file key: {key}")
        self.files[key] = Path(path)
    
    def set_archive(self, format, path):
        if format not in self.files['archives']:
            raise KeyError(f"Unknown archive format: {format}")
        self.files['archives'][format] = Path(path)
    
    def get_directory(self, key):
        return self.directories.get(key)
    
    def get_file(self, key):
        return self.files.get(key)
    
    def get_archive(self, format):
        return self.files['archives'].get(format)
    
    def verify_assets(self):
        """Verify that all tracked assets exist and are accessible"""
        missing = []
        
        # Check directories
        for key, path in self.directories.items():
            if path and not path.exists():
                missing.append(f"Directory {key}: {path}")
        
        # Check files
        for key, path in self.files.items():
            if key == 'archives':
                for format, archive_path in path.items():
                    if archive_path and not archive_path.exists():
                        missing.append(f"Archive {format}: {archive_path}")
            elif path and not path.exists():
                missing.append(f"File {key}: {path}")
        
        return missing

class TestCase:
    def __init__(self, name):
        self.name = name
        self.install = None
        self.run = None
        self.remove = None
    
    def __str__(self):
        status_map = {None: "⚪ UNTESTED", True: "✅ PASSED", False: "❌ FAILED"}
        return (f"{self.name}:\n"
                f"  Install: {status_map[self.install]}\n"
                f"  Run: {status_map[self.run]}\n"
                f"  Remove: {status_map[self.remove]}")

class TestTracker:
    def __init__(self):
        self.cases = {
            'dir': TestCase('Directory Package'),
            'link': TestCase('Linked Package'),
            'exe': TestCase('Executable Package'),
            #'url_exe': TestCase('URL Executable Package'),
            '7z': TestCase('7z Archive Package'),
            #'url_7z': TestCase('URL 7z Archive Package'),
            'zip': TestCase('Zip Archive Package')
        }
    
    def report(self):
        print("\n=== Test Results ===")
        for case in self.cases.values():
            print(f"\n{case}")
        
        # Summary counts
        total = len(self.cases) * 3  # 3 steps per case
        passed = sum(sum(1 for val in [case.install, case.run, case.remove] if val is True)
                    for case in self.cases.values())
        failed = sum(sum(1 for val in [case.install, case.run, case.remove] if val is False)
                    for case in self.cases.values())
        untested = total - (passed + failed)
        
        print(f"\nSummary:")
        print(f"  Total Steps: {total}")
        print(f"  Passed: {passed}")
        print(f"  Failed: {failed}")
        print(f"  Untested: {untested}")


async def run_command(command, input_text=None):
    # Handle both string and list commands
    if isinstance(command, str):
        if os.name == 'nt':
            # On Windows, we need to handle paths with spaces correctly
            import shlex
            args = shlex.split(command)
        else:
            args = command.split()
    else:
        args = command
    
    try:
        # On Windows, we need to use shell=True for .exe files
        if os.name == 'nt' and any(arg.endswith('.exe') for arg in args):
            # Convert list to string for shell=True
            shell_cmd = ' '.join(f'"{arg}"' if ' ' in arg else arg for arg in args)
            process = await asyncio.create_subprocess_shell(
                shell_cmd,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                shell=True
            )
        else:
            process = await asyncio.create_subprocess_exec(
                *args,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                shell=False
            )
        
        if input_text:
            # Split input into lines and send each line
            lines = input_text.decode('utf-8').splitlines()
            for line in lines:
                # Add newline and encode
                input_line = f"{line}\n".encode('utf-8')
                process.stdin.write(input_line)
                await process.stdin.drain()  # Ensure the line is sent
                await asyncio.sleep(0.1)  # Small delay between inputs
            process.stdin.close()
            
        stdout, stderr = await process.communicate()
        return process.returncode, stdout.decode('utf-8'), stderr.decode('utf-8')
    except FileNotFoundError as e:
        raise RuntimeError(f"Command failed: {e}")


async def build_installer():
    returncode, stdout, stderr = await run_command('zig build', ''.encode('utf-8'))
    if returncode != 0:
        raise RuntimeError(f"Build failed: {stderr}")

async def install_popaman(ass_tracker):
    install_path = Path.cwd() # Use Path.cwd() for platform-independence
    popaman_dir = install_path / 'popaman'
    if popaman_dir.exists():
        shutil.rmtree(popaman_dir)
    
    executable_name = 'install-popaman'
    if os.name == 'nt': # Add .exe for windows
        executable_name += '.exe'

    # Get the installer from zig-out/bin
    installer_path = Path('zig-out') / 'bin' / executable_name

    # Verify the installer exists
    if not installer_path.exists():
        raise RuntimeError(f"Installer executable not found at {installer_path}")

    # Construct the command using proper path handling
    command = [
        str(installer_path.absolute()),  # Use absolute path
        str(install_path.absolute()),  # Install to root directory
        '-f'  # Force installation
    ]
    
    try:
        returncode, stdout, stderr = await run_command(command, input_text='y\n'.encode('utf-8'))
        time.sleep(1)
        if returncode != 0:
            raise RuntimeError(f"Installation failed: {stderr}")
        
        # Set the paths in the tracker - use popaman.exe from the installed location
        popaman_exe_name = 'popaman'
        if os.name == 'nt':
            popaman_exe_name += '.exe'
        popaman_exe_path = popaman_dir / 'bin' / popaman_exe_name
        
        if not popaman_exe_path.exists():
            raise RuntimeError(f"Popaman executable not found at {popaman_exe_path}")
            
        ass_tracker.set_file('popaman_exe', popaman_exe_path)
        ass_tracker.set_directory('popaman_bin', popaman_dir / 'bin')
        print(f"Installed at {popaman_dir}")
    except Exception as e:
        print(f"Error during installation: {e}")
        raise

async def build_test_package(ass_tracker):
    # Store the original directory
    original_dir = os.getcwd()
    try:
        # Change to test directory
        os.chdir('test')
        returncode, stdout, stderr = await run_command('zig build', ''.encode('utf-8'))
        time.sleep(1)
        if returncode != 0:
            raise RuntimeError(f"Build failed: {stderr}")
        test_package_name = "test-package"
        if os.name == 'nt':
            test_package_name += ".exe"
        test_package_path = Path('test') / 'zig-out' / 'test-package' 
        test_package_exe = test_package_path / test_package_name
        ass_tracker.set_file('test_package', test_package_exe)
        ass_tracker.set_directory('test_package_dir', test_package_path)
    finally:
        # Always return to the original directory
        os.chdir(original_dir)

async def create_test_archives(ass_tracker):
    # Get the test package path
    test_package_path = ass_tracker.get_file('test_package')
    if not test_package_path:
        raise RuntimeError("test_package file not set")

    # Create archives directory
    archives_dir = Path("test") / "archives"
    archives_dir.mkdir(parents=True, exist_ok=True)
    ass_tracker.set_directory('archives_dir', archives_dir)

    popaman_exe = ass_tracker.get_file('popaman_exe')
    if not popaman_exe:
        raise RuntimeError("popaman_exe file not set")
    
    if not popaman_exe.exists():
        raise RuntimeError(f"Popaman executable not found at {popaman_exe}")
    
    # Create different archive formats
    archive_formats = [
        ("7z", "7z"),
        ("zip", "zip"),
    ]
    
    for format_name, extension in archive_formats:
        archive_name = f"test-package.{extension}"
        archive_path = archives_dir / archive_name
        
        # Remove existing archive if it exists
        if archive_path.exists():
            archive_path.unlink()
        
        # Use popaman to access its default 7zr installation
        command = [
            str(popaman_exe.absolute()),
            "7zr",
            "a",  # Add files to archive
            str(archive_path.absolute()),
            str(test_package_path.absolute())
        ]
        
        # Execute the archive command
        returncode, stdout, stderr = await run_command(command, None)
        if returncode != 0:
            raise RuntimeError(f"Failed to create {format_name} archive: {stderr}")
        
        print(f"Created {format_name} archive at {archive_path}")
        ass_tracker.set_archive(format_name, archive_path)

async def test_package_installation_from_dir(ass_tracker):
    popaman_exe = ass_tracker.get_file('popaman_exe')
    if not popaman_exe:
        raise RuntimeError("popaman_exe file not set")
    
    if not popaman_exe.exists():
        raise RuntimeError(f"Popaman executable not found at {popaman_exe}")
    
    test_package_dir = ass_tracker.get_directory('test_package_dir')
    if not test_package_dir:
        raise RuntimeError("test_package_dir directory not set")
    
    if not test_package_dir.exists():
        raise RuntimeError(f"Test package directory not found at {test_package_dir}")
    
    print("\nTesting directory package installation...")
    try:
        inputs = b'1\ntest-hello\nthis is optional\n'
        # Use list command to avoid path quoting issues
        command = [
            str(popaman_exe.absolute()),
            "install",
            str(test_package_dir.absolute())
        ]
        returncode, stdout, stderr = await run_command(
            command,
            input_text=inputs
        )
        if returncode != 0:
            raise RuntimeError(f"Installation failed: {stderr}")
        print("Installation command completed")
    except Exception as e:
        print(f"Installation failed: {e}")
        raise
    
    print("Verifying installation...")
    # Verify package exists in packages.json
    with open('popaman/lib/packages.json') as f:
        packages = json.load(f)
        assert any(p['keyword'] == 'test-hello' for p in packages['package']), \
            "Package not found in packages.json"
    print("Verification complete")

async def test_package_linking(ass_tracker):
    print("\nTesting linked package installation...")
    popaman_exe = ass_tracker.get_file('popaman_exe')
    if not popaman_exe:
        raise RuntimeError("popaman_exe file not set")
    
    if not popaman_exe.exists():
        raise RuntimeError(f"Popaman executable not found at {popaman_exe}")
    
    test_package_dir = ass_tracker.get_directory('test_package_dir')
    if not test_package_dir:
        raise RuntimeError("test_package_dir directory not set")
    
    if not test_package_dir.exists():
        raise RuntimeError(f"Test package directory not found at {test_package_dir}")
    try:
        inputs = b'1\ntest-hello-link\nthis is optional\n'
        # Use list command to avoid path quoting issues
        command = [
            str(popaman_exe.absolute()),
            "link",
            str(test_package_dir.absolute())
        ]
        returncode, stdout, stderr = await run_command(
            command,
            input_text=inputs
        )
        if returncode != 0:
            raise RuntimeError(f"Installation failed: {stderr}")
        print("Installation command completed")
    except Exception as e:
        print(f"Installation failed: {e}")
        raise
    
    print("Verifying installation...")
    #Verify package exists in packages.json
    with open('popaman/lib/packages.json') as f:
        packages = json.load(f)
        assert any(p['name'] == 'link@test-package' for p in packages['package']), \
            "Package not found in packages.json"
    print("Verification complete")

async def test_package_installation_from_7z(ass_tracker):
    print("\nTesting 7z package installation...")
    popaman_exe = ass_tracker.get_file('popaman_exe')
    if not popaman_exe:
        raise RuntimeError("popaman_exe file not set")
    
    if not popaman_exe.exists():
        raise RuntimeError(f"Popaman executable not found at {popaman_exe}")
    
    test_pkg_path = ass_tracker.get_archive('7z')
    if not test_pkg_path:
        raise RuntimeError("7z archive not set")
    
    if not test_pkg_path.exists():
        raise RuntimeError(f"7z archive not found at {test_pkg_path}")
    
    try:
        inputs = b'1\ntest-hello-7z\nthis is optional\n'
        # Use list command to avoid path quoting issues
        command = [
            str(popaman_exe.absolute()),
            "install",
            str(test_pkg_path.absolute())
        ]
        returncode, stdout, stderr = await run_command(
            command,
            input_text=inputs
        )
        if returncode != 0:
            raise RuntimeError(f"Installation failed: {stderr}")
        print("Installation command completed")
    except Exception as e:
        print(f"Installation failed: {e}")
        raise
    
    print("Verifying installation...")
    with open('popaman/lib/packages.json') as f:
        packages = json.load(f)
        assert any(p['keyword'] == 'test-hello-7z' for p in packages['package']), \
            "Package not found in packages.json"
    print("Verification complete")

async def test_package_installation_from_zip(ass_tracker):
    print("\nTesting zip package installation...")
    popaman_exe = ass_tracker.get_file('popaman_exe')
    if not popaman_exe:
        raise RuntimeError("popaman_exe file not set")
    
    if not popaman_exe.exists():
        raise RuntimeError(f"Popaman executable not found at {popaman_exe}")
    
    test_pkg_path = ass_tracker.get_archive('zip')
    if not test_pkg_path:
        raise RuntimeError("zip archive not set")
    
    if not test_pkg_path.exists():
        raise RuntimeError(f"zip archive not found at {test_pkg_path}")
    
    try:
        inputs = b'1\ntest-hello-zip\nthis is optional\n'
        # Use list command to avoid path quoting issues
        command = [
            str(popaman_exe.absolute()),
            "install",
            str(test_pkg_path.absolute())
        ]
        returncode, stdout, stderr = await run_command(
            command,
            input_text=inputs
        )
        if returncode != 0:
            raise RuntimeError(f"Installation failed: {stderr}")
        print("Installation command completed")
    except Exception as e:
        print(f"Installation failed: {e}")
        raise
    
    print("Verifying installation...")
    with open('popaman/lib/packages.json') as f:
        packages = json.load(f)
        assert any(p['keyword'] == 'test-hello-zip' for p in packages['package']), \
            "Package not found in packages.json"
    print("Verification complete")

async def test_package_removal(ass_tracker):
    print("\nTesting package removal...")
    popaman_exe = ass_tracker.get_file('popaman_exe')
    if not popaman_exe:
        raise RuntimeError("popaman_exe file not set")
    
    if not popaman_exe.exists():
        raise RuntimeError(f"Popaman executable not found at {popaman_exe}")
    
    # Add delays between removals
    for pkg in ['test-hello', 'test-hello-link', 'test-hello-exe', 
                'test-hello-7z', 'test-hello-zip']: 
        # Use list command to avoid path quoting issues
        command = [
            str(popaman_exe.absolute()),
            "remove",
            pkg
        ]
        returncode, stdout, stderr = await run_command(
            command,
            input_text=None
        )
        if returncode != 0:
            # Only raise error if it's not a "package not found" error
            if "Package not found" not in stderr:
                raise RuntimeError(f"Failed to remove package {pkg}: {stderr}")
        time.sleep(0.5)  # Give filesystem time between removals
    
    # Verify package is removed from packages.json
    with open('popaman/lib/packages.json') as f:
        packages = json.load(f)
        assert not any(p['keyword'] == 'test-hello' or 
                      p['keyword'] == 'test-hello-link' or 
                      p['keyword'] == 'test-hello-exe' or 
                      p['keyword'] == 'test-hello-7z' or 
                      p['keyword'] == 'test-hello-zip' for p in packages['package']), \
            "Package still exists in packages.json"

async def test_package_installation_from_exe(ass_tracker):
    popaman_exe = ass_tracker.get_file('popaman_exe')
    if not popaman_exe:
        raise RuntimeError("popaman_exe file not set")
    
    if not popaman_exe.exists():
        raise RuntimeError(f"Popaman executable not found at {popaman_exe}")
    
    test_package_exe = ass_tracker.get_file('test_package')
    if not test_package_exe:
        raise RuntimeError("test_package file not set")
    
    if not test_package_exe.exists():
        raise RuntimeError(f"Test package executable not found at {test_package_exe}")
    
    print("\nTesting executable package installation...")
    try:
        inputs = b'1\ntest-hello-exe\nthis is optional\n'
        # Use list command to avoid path quoting issues
        command = [
            str(popaman_exe.absolute()),
            "install",
            str(test_package_exe.absolute())
        ]
        returncode, stdout, stderr = await run_command(
            command,
            input_text=inputs
        )
        if returncode != 0:
            raise RuntimeError(f"Installation failed: {stderr}")
        print("Installation command completed")
    except Exception as e:
        print(f"Installation failed: {e}")
        raise
    
    print("Verifying installation...")
    # Verify package exists in packages.json
    with open('popaman/lib/packages.json') as f:
        packages = json.load(f)
        assert any(p['keyword'] == 'test-hello' for p in packages['package']), \
            "Package not found in packages.json"
    print("Verification complete")

async def test_package_running(ass_tracker):
    print("\nTesting package execution...")
    try:
        popaman_exe = ass_tracker.get_file('popaman_exe')
        if not popaman_exe:
            raise RuntimeError("popaman_exe file not set")
        
        if not popaman_exe.exists():
            raise RuntimeError(f"Popaman executable not found at {popaman_exe}")
        
        # Test each package type
        packages = [
            'test-hello',
            'test-hello-link',
            'test-hello-exe',
            #'test-hello-url-exe',
            'test-hello-7z',
            #'test-hello-url-7z',
            'test-hello-zip'  
        ]
        
        for pkg in packages:
            # Use list command to avoid path quoting issues
            command = [
                str(popaman_exe.absolute()),
                pkg
            ]
            returncode, stdout, stderr = await run_command(
                command,
                input_text=None
            )
            if returncode != 0:
                raise RuntimeError(f"Package {pkg} execution failed: {stderr}")
            
            # stdout and stderr are already strings, no need to decode
            if 'Hello, world!' not in stdout and 'Hello, world!' not in stderr:
                raise RuntimeError(f"Package {pkg} did not output 'Hello, world!'")
            
            print(f"Package {pkg} executed successfully")
        
        print("All package execution tests passed")
    except Exception as e:
        print(f"Package execution failed: {e}")
        raise



async def test_installation(ass_tracker, test_tracker):
    # Test 1: Directory Package
    try:
        await test_package_installation_from_dir(ass_tracker)
        test_tracker.cases['dir'].install = True
    except Exception as e:
        test_tracker.cases['dir'].install = False
        print(f"Directory installation failed: {e}")

    # Test 2: Linked Package
    try:
        await test_package_linking(ass_tracker)
        test_tracker.cases['link'].install = True
    except Exception as e:
        test_tracker.cases['link'].install = False
        print(f"Link installation failed: {e}")

    # Test 3: Executable Package
    try:
        await test_package_installation_from_exe(ass_tracker)
        test_tracker.cases['exe'].install = True
    except Exception as e:
        test_tracker.cases['exe'].install = False
        print(f"Executable installation failed: {e}")

    # # Test 4: URL Executable Package
    # try:
    #     await test_package_installation_from_url_exe()
    #     tracker.cases['url_exe'].install = True
    # except Exception as e:
    #     tracker.cases['url_exe'].install = False
    #     print(f"URL executable installation failed: {e}")

    # Test 5: 7z Archive Package
    try:
        await test_package_installation_from_7z(ass_tracker)
        test_tracker.cases['7z'].install = True
    except Exception as e:
        test_tracker.cases['7z'].install = False
        print(f"7z archive installation failed: {e}")

    # # Test 6: URL 7z Archive Package
    # try:
    #     await test_package_installation_from_url_7z()
    #     test_tracker.cases['url_7z'].install = True
    # except Exception as e:
    #     test_tracker.cases['url_7z'].install = False
    #     print(f"URL 7z archive installation failed: {e}")

    try:
        await test_package_installation_from_zip(ass_tracker)
        test_tracker.cases['zip'].install = True
    except Exception as e:
        test_tracker.cases['zip'].install = False
        print(f"zip archive installation failed: {e}")



async def cleanup_paths(paths_to_clean):
    """Clean up specified paths in a platform-safe way"""
    for path in paths_to_clean:
        try:
            if path.exists():
                if path.is_dir():
                    shutil.rmtree(path)
                else:
                    path.unlink()
        except Exception as e:
            print(f"Warning: Failed to clean {path}: {e}")

async def cleanup():
    """Clean up test artifacts in a platform-safe way"""
    paths_to_clean = [
        Path("test/zig-out"),
        Path("test/archives"),
        Path("test/.zig-cache"),
        Path("popaman")
    ]
    await cleanup_paths(paths_to_clean)

def parse_args():
    parser = argparse.ArgumentParser(description='Test script for Popaman')
    parser.add_argument('--clean', action='store_true', help='Clean up test artifacts')
    return parser.parse_args()

async def main():
    args = parse_args()
    test_tracker = TestTracker()
    ass_tracker = AssetTracker()

    if args.clean:
        await cleanup()
        return

    print("++ Testing Popaman ++")
    try:
        print("Building test files...")
        try:
            await build_installer()
        except Exception as e:
            test_tracker.cases['dir'].install = False
            print(f"Error: {e}")

        try:
            await install_popaman(ass_tracker)
        except Exception as e:
            test_tracker.cases['dir'].install = False
            print(f"Error: {e}")

        try:
            await build_test_package(ass_tracker)
        except Exception as e:
            test_tracker.cases['dir'].install = False
            print(f"Error: {e}")

        print("Creating test archives...")
        try:
            await create_test_archives(ass_tracker)
        except Exception as e:
            test_tracker.cases['dir'].install = False
            print(f"Error: {e}")
    
        print("Testing installation...")
        try:
            await test_installation(ass_tracker,test_tracker)
        except Exception as e:
            test_tracker.cases['dir'].install = False
            print(f"Error: {e}")

        # Test all package execution
        try:
            await test_package_running(ass_tracker)
            # If we get here, all packages ran successfully
            for case in test_tracker.cases.values():
                case.run = True
        except Exception as e:
            # If any package fails to run, mark all as failed
            # (since we can't easily tell which one failed)
            for case in test_tracker.cases.values():
                case.run = False
            print(f"Package execution failed: {e}")

        # Test package removal
        try:
            await test_package_removal(ass_tracker)
            # If we get here, all packages were removed successfully
            for case in test_tracker.cases.values():
                case.remove = True
        except Exception as e:
            # If any package fails to remove, mark all as failed
            for case in test_tracker.cases.values():
                case.remove = False
            print(f"Package removal failed: {e}")

        # Always show the test report, even if something failed
        test_tracker.report()
        
        # Check if any tests failed
        failed_tests = any(
            any(val is False for val in [case.install, case.run, case.remove])
            for case in test_tracker.cases.values()
        )
        
        if failed_tests:
            print("\nSome tests failed - check the report above for details")
            sys.exit(1)  # Return failure exit code
        else:
            print("\nAll tests completed successfully! 🎉")
            sys.exit(0)  # Return success exit code

    finally:
        print("Cleaning up...")
        # try:
        #     await cleanup()
        # except Exception as e:
        #     print(f"Cleanup error: {e}")


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())