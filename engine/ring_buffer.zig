const std = @import("std");

/// A contiguous, fixed-capacity ring (circular) buffer.
///
/// The buffer stores up to `N - 1` values of `T` in a stack-allocated array of
/// size `N`, where `N` is a power of two chosen at compile time.
pub fn RingBuffer(comptime T: type, comptime N: usize) type {
    comptime {
        if (N == 0 or !std.math.isPowerOfTwo(N))
            @compileError("N must be a power of two");
    }

    return struct {
        const Self = @This();
        const mask: usize = N - 1;

        /// Backing store.
        storage: [N]T = undefined,
        /// Next write index.
        head: usize = 0,
        /// Next read index.
        tail: usize = 0,

        /// Returns the number of items currently in the buffer.
        pub fn len(self: Self) usize {
            return (self.head - self.tail) & mask;
        }

        test len {
            var rb = RingBuffer(u8, 8){};

            std.testing.expectEqual(@as(usize, 0), rb.len());
            rb.push(1);
            std.testing.expectEqual(@as(usize, 1), rb.len());
            rb.pop();
            std.testing.expectEqual(@as(usize, 0), rb.len());
        }

        /// Returns `true` when the buffer holds zero items.
        pub fn isEmpty(self: Self) bool {
            return self.head == self.tail;
        }

        test isEmpty {
            var rb = RingBuffer(u8, 8){};

            std.testing.expectEqual(true, rb.isEmpty());
            rb.push(1);
            std.testing.expectEqual(false, rb.isEmpty());
            rb.pop();
            std.testing.expectEqual(true, rb.isEmpty());
        }

        /// Returns `true` when one more push would fail.
        pub fn isFull(self: Self) bool {
            return ((self.head + 1) & mask) == self.tail;
        }

        test isFull {
            var rb = RingBuffer(u8, 8){};

            std.testing.expectEqual(false, rb.isFull());
            rb.push(1);
            std.testing.expectEqual(false, rb.isFull());
            rb.pop();
            std.testing.expectEqual(false, rb.isFull());
        }

        /// Attempts to push `item`; returns `false` if buffer is full.
        pub fn push(self: *Self, item: T) bool {
            const next = (self.head + 1) & mask;
            if (next == self.tail) return false;
            self.storage[self.head] = item;
            self.head = next;
            return true;
        }

        test push {
            var rb = RingBuffer(u8, 8){};

            std.testing.expectEqual(true, rb.push(1));
            std.testing.expectEqual(false, rb.push(2));
            rb.pop();
            std.testing.expectEqual(true, rb.push(2));
        }

        /// Pops the oldest item or `null` if empty.
        pub fn pop(self: *Self) ?T {
            if (self.head == self.tail) return null;
            const out = self.storage[self.tail];
            self.tail = (self.tail + 1) & mask;
            return out;
        }

        test pop {
            var rb = RingBuffer(u8, 8){};

            std.testing.expectEqual(null, rb.pop());
            rb.push(1);
            std.testing.expectEqual(@as(u8, 1), rb.pop().?);
            std.testing.expectEqual(null, rb.pop());
        }

        /// Clears the buffer in O(1).
        pub fn clear(self: *Self) void {
            self.head = 0;
            self.tail = 0;
        }

        test clear {
            var rb = RingBuffer(u8, 8){};

            rb.push(1);
            rb.clear();
            std.testing.expectEqual(null, rb.pop());
        }
    };
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
