const std = @import("std");

const log = std.log.scoped(.wayland);

pub fn shmCreate(size: usize) !std.posix.fd_t {
    for (0..100) |_| {
        // 100 attempts

        const name = randomShmName();

        const fd = std.c.shm_open(@ptrCast(&name), @bitCast(std.posix.O{
            .ACCMODE = .RDWR,
            .CREAT = true,
            .EXCL = true,
        }), 0o666);

        switch (std.posix.errno(fd)) {
            .SUCCESS => {},
            .EXIST => continue,
            else => |other| {
                log.err("failed to open shm: {}", .{other});
                return std.posix.unexpectedErrno(other);
            },
        }

        errdefer std.posix.close(fd);

        const ret = std.c.shm_unlink(@ptrCast(&name));
        switch (std.posix.errno(ret)) {
            .SUCCESS => {},
            else => |other| {
                log.err("failed to unlink shm: {}", .{other});
                return std.posix.unexpectedErrno(other);
            },
        }

        try std.posix.ftruncate(fd, size);

        return fd;
    }

    return error.FailedToCreateShm;
}

pub fn randomShmName() [32]u8 {
    var buf = [_]u8{0} ** 32;
    var writer = std.io.fixedBufferStream(buf[0..]);

    std.fmt.format(writer.writer(), "/wl-shm-{x:0>16}", .{
        std.crypto.random.int(u64),
    }) catch unreachable;

    std.debug.assert(buf[31] == 0);
    return buf;
}
