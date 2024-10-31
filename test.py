import subprocess
import json
import shutil
from pathlib import Path
import time

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

def test_package_installation():
    print("\nTesting package installation...")
    print("Running installation command...")
    try:
        # Add newline after the '1' and include the next input
        inputs = b'1\nfastfetch\nthis is optional\n'
        process = run_command(
            '.\\portman\\bin\\portman.exe install C:/Users/User/Downloads/fastfetch',
            input_text=inputs
        )
        print("Installation command completed")
    except Exception as e:
        print(f"Installation failed: {e}")
        raise
    
    print("Verifying installation...")
    # Verify package exists in packages.json
    # with open('portman/lib/packages.json') as f:
    #     packages = json.load(f)
    #     assert any(p['keyword'] == 'test-hello' for p in packages['package']), \
    #         "Package not found in packages.json"
    # print("Verification complete")

def test_global_package():
    print("\nTesting global package operations...")
    # Install package globally
    process = run_command(
        'bin\\portman.exe install test_package -g',  # use Windows path
        input_text='test-hello-global\nTest global hello package\n'
    )
    
    # Verify global script exists
    assert Path('bin/test-hello-global.cmd').exists(), \
        "Global script not created"

def test_package_removal():
    print("\nTesting package removal...")
    # Remove package
    process = run_command('bin\\portman.exe remove test-hello')  # use Windows path
    
    # Verify package is removed from packages.json
    with open('lib/packages.json') as f:
        packages = json.load(f)
        assert not any(p['keyword'] == 'test-hello' for p in packages['package']), \
            "Package still exists in packages.json"

def cleanup(test_pkg):
    # Remove test package
    if test_pkg.exists():
        shutil.rmtree(test_pkg)
    
    # Clean up installed packages
    lib_dir = Path('lib')
    bin_dir = Path('bin')
    if lib_dir.exists():
        shutil.rmtree(lib_dir)
    if bin_dir.exists():
        shutil.rmtree(bin_dir)

def main():
    test_pkg = setup()
    try:
       test_package_installation()
    #     test_global_package()
    #     test_package_removal()
    #     print("\nAll tests passed! ✅")
    except Exception as e:
        print(f"\nTest failed: {e} ❌")
        raise
    # finally:
    #     cleanup(test_pkg)

if __name__ == "__main__":
    main()