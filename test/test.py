import subprocess
import json
from pathlib import Path
import time

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

def find_portman_dir():
    """Find the portman installation directory by walking up from the current directory."""
    current_dir = Path(__file__).parent
    while current_dir != current_dir.parent:  # Stop at root
        portman_dir = current_dir / 'portman'
        if portman_dir.exists() and (portman_dir / 'bin' / 'portman.exe').exists():
            return portman_dir
        current_dir = current_dir.parent
    raise RuntimeError("Could not find portman installation directory")

def get_portman_exe():
    """Get the path to the portman executable."""
    return str(find_portman_dir() / 'bin' / 'portman.exe')

def get_packages_json():
    """Get the path to the packages.json file."""
    return find_portman_dir() / 'lib' / 'packages.json'

def run_command_capture_output(cmd):
    print(f"Debug - Command: {cmd}")
    
    if isinstance(cmd, str):
        cmd = cmd.split()
    
    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=False,
        bufsize=0
    )
    
    stdout, stderr = process.communicate()
    
    if process.returncode != 0:
        print(f"Error running {cmd}")
        print(f"stdout: {stdout.decode('utf-8')}")
        print(f"stderr: {stderr.decode('utf-8')}")
        raise RuntimeError(f"Command failed with exit code {process.returncode}")
    
    return stdout, stderr

def run_command(cmd, input_text=None):
    print(f"Debug - Command: {cmd}")
    print(f"Debug - Input text: {repr(input_text)}")
    
    if isinstance(cmd, str):
        cmd = cmd.split()
    
    # Check if this is a URL download command
    is_url_download = any(arg.startswith(('http://', 'https://')) for arg in cmd)
    
    process = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=False,
        bufsize=0
    )
    
    # If we have multiple inputs, send them one at a time with small delays
    if input_text:
        inputs = input_text.split(b'\n')
        for inp in inputs:
            if inp:  # Only send non-empty inputs
                if is_url_download:
                    time.sleep(0.5)
                process.stdin.write(inp + b'\n')
                process.stdin.flush()
                time.sleep(0.1)  # Give the program time to process each input
    
    stdout, stderr = process.communicate()
    
    if process.returncode != 0:
        print(f"Error running {cmd}")
        print(f"stdout: {stdout.decode('utf-8')}")
        print(f"stderr: {stderr.decode('utf-8')}")
        raise RuntimeError(f"Command failed with exit code {process.returncode}")
    
    return process

def setup():
    # Build the project first
    print("Building project...")
    # Run build script with encoded input
    process = run_command('python build.py', ''.encode('utf-8'))
    if process.returncode != 0:
        raise RuntimeError("Build failed")
    process = run_command('install-portman.exe -f', input_text='y\n'.encode('utf-8'))
    if process.returncode != 0:
        raise RuntimeError("Build failed")
    
    # find test package directory
    test_pkg = Path('test/test_package')
    
    return test_pkg

def test_package_running():
    print("\nTesting package execution...")
    try:
        portman_exe = get_portman_exe()
        # Test the installed package
        process = run_command(f'{portman_exe} test-hello')
        stdout, stderr = process.communicate()
        print("=== Debug Output ===")
        print(f"Return code: {process.returncode}")
        print(f"Raw stdout: {stdout}")
        print(f"Decoded stdout: {stdout.decode('utf-8')}")
        print(f"Raw stderr: {stderr}")
        print(f"Decoded stderr: {stderr.decode('utf-8')}")
        print("==================")
        
        assert b'Hello, World!' in stdout or b'Hello, World!' in stderr, \
            "Package 'test-hello' did not output 'Hello, World!'"
        
        # Test the linked package
        process = run_command(f'{portman_exe} test-hello-link')
        stdout, stderr = process.communicate()
        assert b'Hello, World!' in stdout or b'Hello, World!' in stderr, \
            "Package 'test-hello-link' did not output 'Hello, World!'"
        
        # Test the exe package
        process = run_command(f'{portman_exe} test-hello-exe')
        stdout, stderr = process.communicate()
        assert b'Hello, World!' in stdout or b'Hello, World!' in stderr, \
            "Package 'test-hello-exe' did not output 'Hello, World!'"
        
        # Test the url exe package
        process = run_command(f'{portman_exe} test-hello-url-exe')
        stdout, stderr = process.communicate()
        assert b'Hello, World!' in stdout or b'Hello, World!' in stderr, \
            "Package 'test-hello-url-exe' did not output 'Hello, World!'"
        
        # Test the 7z package
        process = run_command(f'{portman_exe} test-hello-7z')
        stdout, stderr = process.communicate()
        assert b'Hello, World!' in stdout or b'Hello, World!' in stderr, \
            "Package 'test-hello-7z' did not output 'Hello, World!'"
        
        # Test the url 7z package
        process = run_command(f'{portman_exe} test-hello-url-7z')
        stdout, stderr = process.communicate()
        assert b'Hello, World!' in stdout or b'Hello, World!' in stderr, \
            "Package 'test-hello-url-7z' did not output 'Hello, World!'"
        
        print("Package execution tests passed")
    except Exception as e:
        print(f"Package execution failed: {e}")
        raise

def test_package_installation_from_dir():
    print("\nTesting package installation...")
    print("Running installation command...")
    try:
        portman_exe = get_portman_exe()
        # Use absolute path for test_package
        test_pkg_path = str(Path('test/test_package').absolute())
        inputs = b'1\ntest-hello\nthis is optional\n'
        process = run_command(
            f'{portman_exe} install ' + test_pkg_path,
            input_text=inputs
        )
        print("Installation command completed")
    except Exception as e:
        print(f"Installation failed: {e}")
        raise
    
    print("Verifying installation...")
    #Verify package exists in packages.json
    with open('portman/lib/packages.json') as f:
        packages = json.load(f)
        assert any(p['keyword'] == 'test-hello' for p in packages['package']), \
            "Package not found in packages.json"
    print("Verification complete")

def test_package_linking():
    print("\nTesting package installation...")
    print("Running installation command...")
    try:
        portman_exe = get_portman_exe()
        # Use absolute path for test_package
        test_pkg_path = str(Path('test/test_package').absolute())
        inputs = b'1\ntest-hello-link\nthis is optional\n'
        process = run_command(
            f'{portman_exe} link ' + test_pkg_path,
            input_text=inputs
        )
        print("Installation command completed")
    except Exception as e:
        print(f"Installation failed: {e}")
        raise
    
    print("Verifying installation...")
    #Verify package exists in packages.json
    with open('portman/lib/packages.json') as f:
        packages = json.load(f)
        assert any(p['name'] == 'link@test_package' for p in packages['package']), \
            "Package not found in packages.json"
    print("Verification complete")

def test_package_removal():
    print("\nTesting package removal...")
    portman_exe = get_portman_exe()
    # Remove package
    process = run_command(f'{portman_exe} remove test-hello')  
    process = run_command(f'{portman_exe} remove test-hello-link')  
    process = run_command(f'{portman_exe} remove test-hello-exe')  
    process = run_command(f'{portman_exe} remove test-hello-url-exe') 
    process = run_command(f'{portman_exe} remove test-hello-7z') 
    process = run_command(f'{portman_exe} remove test-hello-url-7z') 
    
    # Verify package is removed from packages.json
    with open('portman/lib/packages.json') as f:
        packages = json.load(f)
        assert not any(p['keyword'] == 'test-hello' or p['keyword'] == 'test_package-link' or p['keyword'] == 'test_package-exe' or p['keyword'] == 'test_package-url-exe' or p['keyword'] == 'test_package-7z' or p['keyword'] == 'test_package-url-7z' for p in packages['package']), \
            "Package still exists in packages.json"

def test_package_installation_from_exe():
    print("\nTesting package installation...")
    print("Running installation command...")
    try:
        portman_exe = get_portman_exe()
        # Use absolute path for test_package
        test_pkg_path = str(Path('test/test_package/hello.exe').absolute())
        inputs = b'1\ntest-hello-exe\nthis is optional\n'
        process = run_command(
            f'{portman_exe} install ' + test_pkg_path,
            input_text=inputs
        )
        print("Installation command completed")
    except Exception as e:
        print(f"Installation failed: {e}")
        raise
    
    print("Verifying installation...")
    #Verify package exists in packages.json
    with open('portman/lib/packages.json') as f:
        packages = json.load(f)
        assert any(p['keyword'] == 'test-hello' for p in packages['package']), \
            "Package not found in packages.json"
    print("Verification complete")

def test_package_installation_from_url_exe():
    print("\nTesting package installation...")
    print("Running installation command...")
    try:
        portman_exe = get_portman_exe()
        # Use absolute path for test_package
        test_pkg_path = "https://raw.githubusercontent.com/mirror-shades/portman/master/test/test_package/hello.exe"
        inputs = b'1\ntest-hello-url-exe\nthis is optional\n'
        process = run_command(
            f'{portman_exe} install ' + test_pkg_path,
            input_text=inputs
        )
        print("Installation command completed")
    except Exception as e:
        print(f"Installation failed: {e}")
        raise
    
    print("Verifying installation...")
    #Verify package exists in packages.json
    with open('portman/lib/packages.json') as f:
        packages = json.load(f)
        assert any(p['keyword'] == 'test-hello-url-exe' for p in packages['package']), \
            "Package not found in packages.json"
    print("Verification complete")

def test_package_installation_from_7z():
    print("\nTesting package installation...")
    print("Running installation command...")
    try:
        portman_exe = get_portman_exe()
        # Use absolute path for test_package
        test_pkg_path = str(Path('test/test_package.7z').absolute())
        inputs = b'1\ntest-hello-7z\nthis is optional\n'
        process = run_command(
            f'{portman_exe} install ' + test_pkg_path,
            input_text=inputs
        )
        print("Installation command completed")
    except Exception as e:
        print(f"Installation failed: {e}")
        raise

def test_package_installation_from_url_7z():
    print("\nTesting package installation...")  
    print("Running installation command...")
    try:
        portman_exe = get_portman_exe()
        # Use absolute path for test_package
        test_pkg_path = "https://raw.githubusercontent.com/mirror-shades/portman/master/test/test_package.7z"
        inputs = b'1\ntest-hello-url-7z\nthis is optional\n'
        process = run_command(
            f'{portman_exe} install ' + test_pkg_path,
            input_text=inputs
        )
        print("Installation command completed")
    except Exception as e:
        print(f"Installation failed: {e}")
        raise

def main():
    # Initialize our test tracker and set up environment
    tracker = TestTracker()
    test_pkg = setup()
    
    try:
        # Test 1: Directory Package
        try:
            test_package_installation_from_dir()
            tracker.cases['dir'].install = True
        except Exception as e:
            tracker.cases['dir'].install = False
            print(f"Directory installation failed: {e}")

        # Test 2: Linked Package
        try:
            test_package_linking()
            tracker.cases['link'].install = True
        except Exception as e:
            tracker.cases['link'].install = False
            print(f"Link installation failed: {e}")

        # Test 3: Executable Package
        try:
            test_package_installation_from_exe()
            tracker.cases['exe'].install = True
        except Exception as e:
            tracker.cases['exe'].install = False
            print(f"Executable installation failed: {e}")

        # Test 4: URL Executable Package
        try:
            test_package_installation_from_url_exe()
            tracker.cases['url_exe'].install = True
        except Exception as e:
            tracker.cases['url_exe'].install = False
            print(f"URL executable installation failed: {e}")

        # Test 5: 7z Archive Package
        try:
            test_package_installation_from_7z()
            tracker.cases['7z'].install = True
        except Exception as e:
            tracker.cases['7z'].install = False
            print(f"7z archive installation failed: {e}")

        # Test 6: URL 7z Archive Package
        try:
            test_package_installation_from_url_7z()
            tracker.cases['url_7z'].install = True
        except Exception as e:
            tracker.cases['url_7z'].install = False
            print(f"URL 7z archive installation failed: {e}")

        # Test all package execution
        try:
            test_package_running()
            # If we get here, all packages ran successfully
            for case in tracker.cases.values():
                case.run = True
        except Exception as e:
            # If any package fails to run, mark all as failed
            # (since we can't easily tell which one failed)
            for case in tracker.cases.values():
                case.run = False
            print(f"Package execution failed: {e}")

        # Test package removal
        try:
            test_package_removal()
            # If we get here, all packages were removed successfully
            for case in tracker.cases.values():
                case.remove = True
        except Exception as e:
            # If any package fails to remove, mark all as failed
            for case in tracker.cases.values():
                case.remove = False
            print(f"Package removal failed: {e}")

    finally:
        # Always show the test report, even if something failed
        tracker.report()
        
        # Check if any tests failed
        failed_tests = any(
            any(val is False for val in [case.install, case.run, case.remove])
            for case in tracker.cases.values()
        )
        
        if failed_tests:
            raise RuntimeError("Some tests failed - check the report above for details")
        else:
            print("\nAll tests completed successfully! 🎉")

if __name__ == "__main__":
    main()
