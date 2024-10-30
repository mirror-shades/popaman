import os

def main():
    #if install-portman.exe exists, delete it
    if os.path.exists("install-portman.exe"):
        os.remove("install-portman.exe")    
    #run zig build-exe ./src/main.zig --name portman -fstrip
    os.system("zig build-exe ./src/main.zig --name install-portman -fstrip")
    #delete portman.exe.obj
    os.remove("install-portman.exe.obj")

if __name__ == "__main__":
    main()

