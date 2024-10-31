# Building and Installing Portman

Build the executable:

```
python build.py
```

Install Portman:

```
./install-portman.exe [directory]
```

To install a package to the global list, use the install command with the `-g` flag:

```
portman install <package path> -g
```

# Global Packages:

Global packages are available to all users on the system. They are accessed by adding a .sh file to the `portman/bin` directory which is in the PATH.
If a package wasn't installed globally it can be still be added to the global list using the global command with the `-a` flag:

```
portman global <package> -a
```

Or remove an existing package from the global list, use the global command with the `-r` flag:

```
portman global <package> -r
```

The format for the .sh file is as follows:

```
set EXE_PATH=%~dp0\..\lib\directory_name\path\to\executable.exe
"%EXE_PATH%" %*
```

# Package Format:

The `packages.json` file defines how Portman locates and manages packages. Here is an example assuming the package binary is located at `portman/lib/directory_name/path/to/executable.exe`:

```json
{
  "name": "directory_name", // Name of the package directory in lib/
  "path": "path/to/executable.exe", // Path to the executable from the lib/directory_name directory
  "keyword": "keyword_to_use", // Command keyword to invoke the package
  "global": true, // Whether package is globally available
  "description": "optional description" // Description of the package
}
```

Manual installation can be done by adding the portable package to the `lib` directory and adding the `packages.json` entry for it.
