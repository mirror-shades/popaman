import os
import shutil
import time
import asyncio
from pathlib import Path


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
            'url_exe': TestCase('URL Executable Package'),
            '7z': TestCase('7z Archive Package'),
            'url_7z': TestCase('URL 7z Archive Package')
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
    # Split command into program and arguments
    args = command.split()
    
    # Debug output
    print("Debug - Command:", command)
    print("Debug - Input text:", input_text)
    
    process = await asyncio.create_subprocess_exec(
        *args,
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE
    )
    
    if input_text:
        process.stdin.write(input_text)
        process.stdin.close()
    stdout, stderr = await process.communicate()
    return process.returncode, stdout.decode('utf-8'), stderr.decode('utf-8')


async def build_installer():
    returncode, stdout, stderr = await run_command('zig build', ''.encode('utf-8'))
    if returncode != 0:
        raise RuntimeError(f"Build failed: {stderr}")

async def install_popaman():
    install_path = Path.cwd() # Use Path.cwd() for platform-independence
    popaman_dir = install_path / 'popaman'
    if popaman_dir.exists():
        shutil.rmtree(popaman_dir)
    
    executable_name = 'install-popaman'
    if os.name == 'nt': # Add .exe for windows
        executable_name += '.exe'

    # Construct the command using os.path.join for platform compatibility
    command = [
        str(Path('zig-out') / 'bin' / executable_name),
        '-f',
        str(install_path)
    ]
    
    returncode, stdout, stderr = await run_command(
        ' '.join(command), # Join the command list into a string
        input_text='y\n'.encode('utf-8')
    )
    time.sleep(1)
    if returncode != 0:
        raise RuntimeError(f"Installation failed: {stderr}")
    
async def build_test_package():
    # Store the original directory
    original_dir = os.getcwd()
    try:
        # Change to test directory
        os.chdir('test')
        returncode, stdout, stderr = await run_command('zig build', ''.encode('utf-8'))
        time.sleep(1)
        if returncode != 0:
            raise RuntimeError(f"Build failed: {stderr}")
    finally:
        # Always return to the original directory
        os.chdir(original_dir)

async def create_test_archives():
    # Get the test package path
    test_package_name = "test-package"
    if os.name == 'nt':
        test_package_name += ".exe"
    
    # Define paths
    test_package_path = str(Path("test") / "zig-out" / test_package_name)
    archives_dir = Path("test") / "archives"
    
    # Create archives directory if it doesn't exist
    os.makedirs(archives_dir, exist_ok=True)
    
    # Get 7zr path from popaman installation
    seven_zip_path = str(Path("popaman") / "lib" / "7zr" / ("7zr.exe" if os.name == 'nt' else "7zr"))
    
    # Create different archive formats - only use formats supported by 7zr
    archive_formats = [
        ("7z", "7z"),
        ("zip", "zip"),
    ]
    
    for format_name, extension in archive_formats:
        archive_path = str(archives_dir / f"test-package.{extension}")
        
        # Remove existing archive if it exists
        if os.path.exists(archive_path):
            os.remove(archive_path)
        
        # Create archive command
        if format_name in ["7z", "zip"]:
            # Direct 7z/zip creation
            command = f"{seven_zip_path} a {archive_path} {test_package_path}"
            
            # Execute the archive command
            returncode, stdout, stderr = await run_command(command, None)
            if returncode != 0:
                raise RuntimeError(f"Failed to create {format_name} archive: {stderr}")
            
            print(f"Created {format_name} archive at {archive_path}")

async def main():
    tracker = TestTracker()
    print("Testing Popaman...")
    print("Building test files...")
    try:
        await build_installer()
    except Exception as e:
        tracker.cases['dir'].install = False
        print(f"Error: {e}")

    try:
        await install_popaman()
    except Exception as e:
        tracker.cases['dir'].install = False
        print(f"Error: {e}")

    try:
        await build_test_package()
    except Exception as e:
        tracker.cases['dir'].install = False
        print(f"Error: {e}")

    print("Creating test archives...")
    try:
        await create_test_archives()
    except Exception as e:
        tracker.cases['dir'].install = False
        print(f"Error: {e}")

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())