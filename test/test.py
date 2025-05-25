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
    install_path = 'C:\\dev\\zig\\popaman'
    if os.path.exists(os.path.join(install_path, 'popaman')):
        shutil.rmtree(os.path.join(install_path, 'popaman'))
    
    returncode, stdout, stderr = await run_command(
        'zig-out/bin/install-popaman.exe -f C:\\dev\\zig\\popaman',
        input_text='y\n'.encode('utf-8')
    )
    time.sleep(1)
    if returncode != 0:
        raise RuntimeError(f"Installation failed: {stderr}")

async def main():
    tracker = TestTracker()
    await build_installer()
    await install_popaman()


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())