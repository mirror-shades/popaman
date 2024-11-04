import os

def main():
    # Clean previous builds
    if os.path.exists("install-popaman.exe"):
        os.remove("install-popaman.exe")    
    
    # Build command with main file (it will find imports automatically)
    build_cmd = "zig build-exe src/main.zig " \
                "--name install-popaman " \
                "-fstrip"
    
    # Execute build command
    os.system(build_cmd)
    
    # Clean up object files
    if os.path.exists("install-popaman.exe.obj"):
        os.remove("install-popaman.exe.obj")

if __name__ == "__main__":
    main()