const std = @import("std");

pub fn isInstallCommand(cmd: []const u8) bool {
    return std.mem.eql(u8, cmd, "i") or 
           std.mem.eql(u8, cmd, "install") or
           std.mem.eql(u8, cmd, "-i") or
           std.mem.eql(u8, cmd, "-install") or
           std.mem.eql(u8, cmd, "--i") or
           std.mem.eql(u8, cmd, "--install");
}

pub fn isRemoveCommand(cmd: []const u8) bool {
    return std.mem.eql(u8, cmd, "r") or 
           std.mem.eql(u8, cmd, "rm") or
           std.mem.eql(u8, cmd, "remove") or
           std.mem.eql(u8, cmd, "-r") or
           std.mem.eql(u8, cmd, "-remove") or
           std.mem.eql(u8, cmd, "--r") or
           std.mem.eql(u8, cmd, "--remove");
}

pub fn isGlobalizeCommand(cmd: []const u8) bool {
    return std.mem.eql(u8, cmd, "globalize") or 
           std.mem.eql(u8, cmd, "-globalize") or
           std.mem.eql(u8, cmd, "--globalize");
}

pub fn isListCommand(cmd: []const u8) bool {
    return std.mem.eql(u8, cmd, "l") or 
           std.mem.eql(u8, cmd, "ls") or
           std.mem.eql(u8, cmd, "list") or
           std.mem.eql(u8, cmd, "-l") or
           std.mem.eql(u8, cmd, "-list") or
           std.mem.eql(u8, cmd, "--l") or
           std.mem.eql(u8, cmd, "--list");
}

pub fn isLinkCommand(cmd: []const u8) bool {
    return std.mem.eql(u8, cmd, "ln") or 
           std.mem.eql(u8, cmd, "link") or
           std.mem.eql(u8, cmd, "-ln") or
           std.mem.eql(u8, cmd, "-link") or
           std.mem.eql(u8, cmd, "--ln") or
           std.mem.eql(u8, cmd, "--link");
}

pub fn isGlobalFlag(flag: []const u8) bool {
    return std.mem.eql(u8, flag, "g") or 
           std.mem.eql(u8, flag, "global") or
           std.mem.eql(u8, flag, "-g") or
           std.mem.eql(u8, flag, "-global") or
           std.mem.eql(u8, flag, "--g") or
           std.mem.eql(u8, flag, "--global");
}

pub     fn isAddFlag(flag: []const u8) bool {
    return std.mem.eql(u8, flag, "a") or 
           std.mem.eql(u8, flag, "add") or
           std.mem.eql(u8, flag, "-a") or
           std.mem.eql(u8, flag, "-add") or
           std.mem.eql(u8, flag, "--a") or
           std.mem.eql(u8, flag, "--add");
}

pub fn isRemoveFlag(flag: []const u8) bool {
    return std.mem.eql(u8, flag, "r") or 
           std.mem.eql(u8, flag, "rm") or
           std.mem.eql(u8, flag, "-r") or
           std.mem.eql(u8, flag, "-rm") or
           std.mem.eql(u8, flag, "--r") or
           std.mem.eql(u8, flag, "--rm");
}

pub fn isVerboseFlag(flag: []const u8) bool {
    return std.mem.eql(u8, flag, "v") or 
           std.mem.eql(u8, flag, "verbose") or
           std.mem.eql(u8, flag, "-v") or
           std.mem.eql(u8, flag, "-verbose") or
           std.mem.eql(u8, flag, "--v") or
           std.mem.eql(u8, flag, "--verbose");
}