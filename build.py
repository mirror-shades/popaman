import os

def main():
    # Clean previous builds
    if os.path.exists("install-popaman.exe"):
        os.remove("install-popaman.exe")    
    
    build_cmd = "zig build-exe src/main.zig " \
                "--name install-popaman " \
                "-fstrip " \
                "-freference-trace " \
                "-target x86_64-windows-gnu " \
                "assets/app.rc"
    
    # Execute build command
    os.system(build_cmd)
    
    # Clean up object files
    if os.path.exists("install-popaman.exe.obj"):
        os.remove("install-popaman.exe.obj")

if __name__ == "__main__":
    main()