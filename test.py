import subprocess
import json
import shutil
from pathlib import Path
import time

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
    
    process = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=False,
        bufsize=0  # Add unbuffered mode
    )
    
    # If we have multiple inputs, send them one at a time with small delays
    if input_text:
        inputs = input_text.split(b'\n')
        for inp in inputs:
            if inp:  # Only send non-empty inputs
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
    test_pkg = Path('test_package')
    
    return test_pkg

def test_package_running():
    print("\nTesting package execution...")
    try:
        # Test the installed package
        process = run_command('.\\portman\\bin\\portman.exe test-hello')
        stdout, stderr = process.communicate()
        print("=== Debug Output ===")
        print(f"Return code: {process.returncode}")
        print(f"Raw stdout: {stdout}")
        print(f"Decoded stdout: {stdout.decode('utf-8')}")
        print(f"Raw stderr: {stderr}")
        print(f"Decoded stderr: {stderr.decode('utf-8')}")
        print("==================")
        
        assert b'Hello, World!' in stdout or b'Hello, World!' in stderr, \
            "Package 'test-hello' did not output 'hello'"
        
        # Test the linked package
        process = run_command('.\\portman\\bin\\portman.exe link-test-hello')
        stdout, stderr = process.communicate()
        assert b'Hello, World!' in stdout or b'Hello, World!' in stderr, \
            "Package 'link-test-hello' did not output 'hello'"
        
        print("Package execution tests passed")
    except Exception as e:
        print(f"Package execution failed: {e}")
        raise

def test_package_installation():
    print("\nTesting package installation...")
    print("Running installation command...")
    try:
        # Use absolute path for test_package
        test_pkg_path = str(Path('test_package').absolute())
        inputs = b'1\ntest-hello\nthis is optional\n'
        process = run_command(
            '.\\portman\\bin\\portman.exe install ' + test_pkg_path,
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
        # Use absolute path for test_package
        test_pkg_path = str(Path('test_package').absolute())
        inputs = b'1\nlink-test-hello\nthis is optional\n'
        process = run_command(
            '.\\portman\\bin\\portman.exe link ' + test_pkg_path,
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
    # Remove package
    process = run_command('portman\\bin\\portman.exe remove test-hello')  # use Windows path
    process = run_command('portman\\bin\\portman.exe remove link-test-hello')  # use Windows path
    
    # Verify package is removed from packages.json
    with open('portman/lib/packages.json') as f:
        packages = json.load(f)
        assert not any(p['keyword'] == 'test-hello' or p['name'] == 'link@test_package' for p in packages['package']), \
            "Package still exists in packages.json"

def main():
    test_pkg = setup()
    try:
       test_package_installation()
       test_package_linking()
       test_package_running()
       test_package_removal()
       print("\nAll tests passed! ✅")
    except Exception as e:
        print(f"\nTest failed: {e} ❌")
        raise

if __name__ == "__main__":
    main()