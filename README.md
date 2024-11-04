# Portman (Portable Package Manager 📦)

<img style="display: block; margin: 0 auto;" src="portman.png" alt="Portman Logo" width="150"/>

Portman is a lightweight package manager for managing portable Windows applications. It allows you to install, manage, and run portable apps from a centralized location with optional global access. It focuses on simplicity and ease of use, allowing you to install and run portable applications with a few simple commands.

## Features

- Install and manage portable applications from various sources:
  - Local directories
  - Executable files
  - Compressed archives (`.zip`, `.tar`, `.gz`, `.7z`, `.rar`)
  - URLs pointing to executables or compressed files
- Global or local package installation
- Simple command-line interface
- JSON-based package management
- Automatic PATH management
- Support for linking external packages

## Technical Highlights

- Written in Zig for maximum portability and performance
- Memory-safe implementation using Arena allocators
- Robust error handling and user feedback
- Extensible JSON-based package configuration
- Utilizes `7zr` for extracting compressed archives

## Design Philosophy

- Self-contained and portable by design
- Minimal dependencies for reliability
- Flexible installation options (global/local)
- Simple but powerful command-line interface
- Extensible to support various package formats and sources

## Building and Installing Portman

To build from source, you will need Python for the build script and Zig 0.14 for compilation. Run the `build.py` script to compile the installer:

```
python build.py
```

The Portman installation executable will create an installation directory in the current working directory. It also accepts optional arguments to specify the installation directory, force overwrite an existing installation, or skip adding Portman to the PATH.

```
./install-portman.exe [directory] [-f] [-no-path]
```

- `directory`: Optional. Specify the installation directory.
- `-f`: Force overwrite an existing installation.
- `-no-path`: Skip adding Portman to the system PATH.

## Using Portman

Portman provides a simple command-line interface to manage your portable applications.

### Installing a Package

To install a package, use the `install` command followed by the package source. Packages can be installed from local directories, executable files, compressed archives, or URLs.

```
portman install <package path> [options]
```

Options:

- `-g`: Install the package globally (adds to the system PATH).

Examples:

- Install from a local directory:

  ```
  portman install path/to/local/package
  ```

- Install an executable file:

  ```
  portman install path/to/executable.exe
  ```

- Install from a compressed archive:

  ```
  portman install path/to/archive.7z
  ```

- Install from a URL:

  ```
  portman install https://example.com/package.exe
  ```

- Install globally:

  ```
  portman install <package source> -g
  ```

### Linking a Package

Link an existing package from another location without copying the files.

```
portman link <path> [options]
```

Options:

- `-g`: Link the package globally (adds to the system PATH).

Examples:

- Link a package from a local directory:

  ```
  portman link path/to/package -g
  ```

### Global Packages

Global packages are available to all users on the system and can be accessed from any command prompt. When a package is installed globally, a `.cmd` file is added to the `portman/bin` directory, which is included in the system PATH.

If a package was not initially installed globally, you can add it to the global list:

```
portman global <package> -a
```

Or remove an existing package from the global list, use the global command with the `-r` flag:

```
portman global <package> -r

```

### Running a Package

Once installed, you can run a package using its assigned keyword:

```
portman <keyword> [options]
```

Examples:

- Run a package:

  ```
  portman myapp --help
  ```

### Removing a Package

To remove an installed package:

```
portman remove <package>
```

### Listing Packages

List all available packages:

```
portman list
```

List all available packages with descriptions:

```
portman list -v
```

## Package Format

The `packages.json` file defines how Portman locates and manages packages. Below is an example entry in `packages.json`:

```json
{
  "name": "directory_name", // Name of the package directory in lib/
  "path": "path/to/executable.exe", // Path to the executable from the lib/directory_name directory
  "keyword": "keyword_to_use", // Command keyword to invoke the package
  "global": true, // Whether package is globally available
  "description": "optional description" // Description of the package
}
```

- `name`: Name of the package directory in `lib/`.
- `path`: Path to the executable from the `lib/directory_name` directory.
- `keyword`: Command keyword to invoke the package.
- `global`: Whether the package is globally available.
- `description`: Optional description of the package.

Manual installation can be done by adding the portable package to the `lib` directory and adding the `packages.json` entry for it.

## Dependencies

Portman utilizes `7zr` (part of the 7-Zip suite) for extracting compressed archives. Ensure that `7zr` is installed and accessible in your system PATH.

## Troubleshooting

- **Command Not Found**: Ensure that `portman` is added to your system PATH. You can add it by running the batch file `PATH.bat` in the lib directory.
- **Installation Errors**: Verify that the package source is correct and accessible.
- **Extraction Failures**: Make sure `7zr` is installed and available.

## Contributing

Contributions are welcome! Please submit issues or pull requests to help improve Portman.

## License

[GNU GPLV2](LICENSE)

## Acknowledgments

- Thanks to the Zig community for their REALLY cool language and tooling and thank you to the 7-Zip team for making 7zr.

---

Feel free to explore, contribute, and customize Portman to fit your portable application management needs!

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
- [x] add 7zip dependency on install

- [ ] add support for installing from compressed files
- [ ] add edge cases and negative tests to test script
