<img src="assets/popaman-logo.png" alt="popaman Logo" width=""/>

## (Po)rtable (Pa)ckage (Man)ager

popaman is a lightweight package manager for managing portable applications. It allows you to install, manage, and run portable apps from a centralized location with optional global access. It focuses on simplicity and ease of use, allowing you to install and run portable applications with a few simple commands.

## Features

- Install and manage portable applications from various sources:
  - Local directories
  - Executable files
  - Compressed archives (uses 7z for extraction currently)
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

## Design Philosophy

- Self-contained and portable by design
- Minimal dependencies for reliability
- Flexible installation options (global/local)
- Simple but powerful command-line interface
- Extensible to support various package formats and sources

## Building and Installing popaman

To build from source, Zig 0.14 for compilation. Run the `zig build` to compile the installer. The popaman installation executable will try and create an installation directory in the current working directory. It also accepts optional arguments to specify the installation directory, force overwrite an existing installation, or skip adding popaman to the PATH.

```
./install-popaman.exe [directory] [-f] [-no-path]
```

- `directory`: Optional. Specify the installation directory.
- `-f`: Force overwrite an existing installation.
- `-no-path`: Skip adding popaman to the system PATH.

## Using popaman

popaman provides a simple command-line interface to manage your portable applications.

### Installing a Package

To install a package, use the `install` command followed by the package source. Packages can be installed from local directories, executable files, compressed archives, or URLs.

```
popaman install <package path> [options]
```

Options:

- `-g`: Install the package globally (adds to the system PATH).

Examples:

- Install from a local directory:

  ```
  popaman install path/to/local/package
  ```

- Install an executable file:

  ```
  popaman install path/to/executable.exe
  ```

- Install from a compressed archive:

  ```
  popaman install path/to/archive.7z
  ```

- Install from a URL:

  ```
  popaman install https://example.com/package.exe
  ```

- Install globally:

  ```
  popaman install <package source> -g
  ```

### Linking a Package

Link an existing package from another location without copying the files.

```
popaman link <path> [options]
```

Options:

- `-g`: Link the package globally (adds to the system PATH).

Examples:

- Link a package from a local directory:

  ```
  popaman link path/to/package -g
  ```

### Global Packages

Global packages are available to all users on the system and can be accessed from any command prompt. When a package is installed globally, a `.cmd` file is added to the `popaman/bin` directory, which is included in the system PATH.

If a package was not initially installed globally, you can add it to the global list using the `globalize` command with the `-a` flag:

```
popaman globalize <package> -a
```

Or remove an existing package from the global list using the `globalize` command with the `-r` flag:

```
popaman globalize <package> -r
```

### Running a Package

Once installed, you can run a package using its assigned keyword:

```
popaman <keyword> [options]
```

Examples:

- Run a package:

  ```
  popaman myapp --help
  ```

### Removing a Package

To remove an installed package:

```
popaman remove <package>
```

### Listing Packages

List all available packages:

```
popaman list
```

List all available packages with descriptions:

```
popaman list -v
```

## Package Format

The `packages.json` file defines how popaman locates and manages packages. Below is an example entry in `packages.json`:

```json
{
  "name": "directory_name", // Name of the package directory in lib/
  "path": "path/to/executable", // Path to the executable from the lib/directory_name directory
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

popaman utilizes `7zr` (part of the 7-Zip suite) for extracting compressed archives. Ensure that `7zr` is installed and accessible in your system PATH.

## Troubleshooting

- **Command Not Found**: Ensure that `popaman` is added to your system PATH. You can add it by running the batch file `PATH.bat` in the lib directory.
- **Installation Errors**: Verify that the package source is correct and accessible.
- **Extraction Failures**: Make sure `7zr` is installed and available.

## Contributing

Contributions are welcome! Please submit issues or pull requests to help improve popaman.

## License

[GNU GPLV2](LICENSE)

## Acknowledgments

- Thanks to the Zig community for their REALLY cool language and tooling and thank you to the 7-Zip team for making 7zr.

---

Feel free to explore, contribute, and customize popaman to fit your portable application management needs!

## TODO

- [x] Usage: popaman <command> [options]
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

- [ ] fix bug with relative paths
- [ ] add native support for installing from compressed files
- [ ] add edge cases and negative tests to test script
