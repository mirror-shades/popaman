/// Main error types for the application
pub const ErrorType = error{
    // File operations
    FileNotFound,
    FileAccessDenied,
    InvalidFilePath,
    
    // Configuration errors
    InvalidConfiguration,
    MissingDependency,
    
    // Runtime errors
    InvalidArgument,
    OperationFailed,
    
    // System errors
    SystemError,
    OutOfMemory,
};

/// Standard exit codes for different error categories
pub const ExitCode = enum(u8) {
    SUCCESS = 0x00,
    GENERAL_ERROR = 0x01,
    INVALID_ARGUMENT = 0x02,
    FILE_ERROR = 0x03,
    CONFIG_ERROR = 0x04,
    SYSTEM_ERROR = 0x05,
    UNKNOWN_ERROR = 0xFF,
};

pub fn getExitCode(err: ErrorType) ExitCode {
    switch (err) {
        error.FileNotFound => return ExitCode.FILE_ERROR,
        error.FileAccessDenied => return ExitCode.FILE_ERROR,
        error.InvalidFilePath => return ExitCode.FILE_ERROR,
        error.InvalidConfiguration => return ExitCode.CONFIG_ERROR,
        error.MissingDependency => return ExitCode.CONFIG_ERROR,
        error.InvalidArgument => return ExitCode.INVALID_ARGUMENT,
        error.OperationFailed => return ExitCode.GENERAL_ERROR,
        error.SystemError => return ExitCode.SYSTEM_ERROR,
        error.OutOfMemory => return ExitCode.SYSTEM_ERROR,
    }
}
