# Portman (Portable Package Manager📦)

<img style="display: block; margin: 0 auto;" src="portman.png" alt="Portman Logo" width="150"/>

Portman is a lightweight package manager for managing portable Windows applications. It allows you to install, manage, and run portable apps from a centralized location with optional global access. It focuses on simplicity and ease of use allowing you to install and run portable applications with a few simple commands.

## Features

- Install and manage portable applications
- Global or local package installation
- Simple command-line interface
- JSON-based package management
- Automatic PATH management

## Technical Highlights

- Written in Zig for maximum portability and performance
- Memory-safe implementation using Arena allocators
- Robust error handling and user feedback
- Extensible JSON-based package configuration

## Design Philosophy

- Self-contained and portable by design
- Minimal dependencies for reliability
- Flexible installation options (global/local)
- Simple but powerful command-line interface

## Building and Installing Portman

To build from source you will need Python for the build and Zig 0.14 for compilation. Just run the build.py script to compile the installer.

```
python build.py
```

the portman installation executable will create an installation directory in the current working directory. It also accepts an optional argument to specify the installation directory if you want to install it in a different directory. There is a -f flag to force overwrite an existing installation and a -no-path flag to skip adding portman to the PATH.

```
./install-portman.exe [directory] [-f] [-no-path]
```

To install a package to the global list, use the install command with the `-g` flag:

```
portman install <package path> -g
```

## Global Packages:

Global packages are available to all users on the system. They are accessed by adding a .cmd file to the `portman/bin` directory which is in the PATH.
If a package wasn't installed globally it can be still be added to the global list using the global command with the `-a` flag:

```
portman global <package> -a
```

Or remove an existing package from the global list, use the global command with the `-r` flag:

```
portman global <package> -r
```

The format for the .cmd file is as follows:

```
set EXE_PATH=%~dp0\..\lib\directory_name\path\to\executable.exe
"%EXE_PATH%" %*
```

## Package Format:

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

## TODO

- [x] Usage: portman <command> [options]
- [x] install <package> Install a package (currently only supports installing from a downloaded binary)
- [x] install <package> -g Install a package globally
- [x] global <package> -a Add package to global list
- [x] global <package> -r Remove package from global list
- [x] remove <package> Remove a package
- [x] link <path> Link a package from elsewhere
- [x] list List all available packages
- [x] list -v List all available packages with descriptions
- [x] test script completed
- [x] add support for installing binaries from URLS

- [ ] add 7zip dependency on install
- [ ] add support for installing from compressed files
- [ ] add edge cases and negative tests to test script
