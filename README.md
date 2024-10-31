# Building and Installing Portman

1. Build the executable:

   ```
   python build.py
   ```

2. Install Portman:

   ```
   ./install-portman.exe
   ```

   To install a package to the global list, use the install command with the `-g` flag:

   ```
   portman install <package> -g
   ```

3. Global Packages:
   Global packages are available to all users on the system. They are accessed by adding a .sh file to the `portman/bin` directory which is in the PATH.
   If a package wasn't installed globally it can be still be added to the global list using the global command with the `-a` flag:

   ```
   portman global <package> -a
   ```

   Or remove an existing package from the global list, use the global command with the `-r` flag:

   ```
   portman global <package> -r
   ```

4. Package Format:
   The `packages.json` file uses the following format for each package:

   ```json
   {
     "name": "directory_name", // Name of the package directory
     "path": "executable.exe", // Path to the executable
     "keyword": "keyword_to_use", // Command keyword to invoke the package
     "global": true, // Whether package is globally available
     "description": "optional description" // Description of the package
   }
   ```

   This defines how Portman locates and manages packages in the system.
