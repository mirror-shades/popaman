     :: exe wrapper
     :: path to the executable
     set EXE_PATH=%~dp0\..\lib\packages\fastfetch\fastfetch.exe
     :: call the executable with any provided arguments
     "%EXE_PATH%" %* 