import os
import sys
import time
import shutil

def build(release):
    # Clean previous builds
    try:
        if os.path.exists("install-popaman.exe"):
            os.remove("install-popaman.exe")    
        
        build_cmd = "zig build-exe src/main.zig " \
                "--name install-popaman " \
                "-fstrip " \
                "-freference-trace " \
                "-target x86_64-windows-gnu "
        
        if release:
            build_cmd += "-O ReleaseFast "
        
        build_cmd += "assets/app.rc"

        print("building with: " + build_cmd)
        
        # Execute build command
        os.system(build_cmd)
        
        # Clean up object files
        if os.path.exists("install-popaman.exe.obj"):
            os.remove("install-popaman.exe.obj")
        return 0
    except Exception as e:
        print("Error building: " + str(e))
        return 1

def create_release():
    passed = 0

    # Check if install-popaman.exe exists before proceeding
    if not os.path.exists("install-popaman.exe"):
        print("Error: install-popaman.exe not found")
        passed = 1
    
    # Check if popaman directory exists
    elif not os.path.exists("popaman"):
        print("Error: popaman directory not found")
        passed = 1

    #Check if 7zr.exe exists
    elif not os.path.exists(".\\popaman\\lib\\7zr\\7zr.exe"):
        print("Error: 7zr.exe not found at .\\popaman\\lib\\7zr\\7zr.exe")
        passed = 1

    # Only proceed if all checks are passing
    if passed == 0:
        try:
            # Make a release folder
            if not os.path.exists("release"):
                os.makedirs("release")

            # Copy executable
            shutil.copy("install-popaman.exe", "release/install-popaman.exe")

            # Create archives
            shutil.make_archive("release/popaman", "zip", "popaman")
            os.system('.\\popaman\\lib\\7zr\\7zr.exe a release\\popaman.7z .\\popaman\\*')
            shutil.make_archive("release/popaman", "gztar", "popaman")
        except Exception as e:
            print(f"Error creating release: {str(e)}")
            passed = 1

    return passed

def release():
    # Verify tests pass
    passedTests = os.system("python test/test.py")
    if not passedTests == 0:
        print("\n\nTests failed. Exiting.")
        return

    # Build release with optimizations
    print("\n\nTests passed. Building release.")
    passedBuild = build(True)
    if not passedBuild == 0:
        print("\n\nBuild failed. Exiting.")
        return
    
    # Create release folder
    print("\n\nBuild successful. Creating release folder.")
    if not create_release() == 0:
        print("\n\nRelease creation failed. Exiting.")
        return
    
    print("\n\nRelease created successfully.")
    return



def main():
    if len(sys.argv) <= 1:
        build(False)
        return
        
    if sys.argv[1] in ["release", "-release", "--release", "r", "-r", "--r"]:
        # backup release folder
        timestamp = time.strftime("%Y%m%d_%H%M%S")
        backup_name = f"release_backup_{timestamp}"
        
        # Remove any existing backup first
        if os.path.exists(backup_name):
            shutil.rmtree(backup_name)
            
        # Backup existing release folder if it exists
        if os.path.exists("release"):
            try:
                shutil.copytree("release", backup_name)
                shutil.rmtree("release")
            except Exception as e:
                print(f"Error backing up release folder: {str(e)}")
                return
                
        try:
            release()
            # Clean up backup on success
            if os.path.exists(backup_name):
                shutil.rmtree(backup_name)
                
        except Exception as e:
            print(f"Error creating release: {str(e)}")
            # Restore backup if release failed
            if os.path.exists(backup_name):
                if os.path.exists("release"):
                    shutil.rmtree("release")
                shutil.copytree(backup_name, "release")
                shutil.rmtree(backup_name)
            
        return
        
    build(False)

if __name__ == "__main__":
    main()
