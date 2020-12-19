const std = @import("std");

const pike = @import("pike");
const zap = @import("zap");

// From: https://github.com/lithdew/snow/blob/master/sync.zig
/// Async-friendly Mutex ported from Zig's standard library to be compatible
/// with scheduling methods exposed by pike.
pub const Mutex = struct {
    mutex: std.Mutex = .{},
    head: usize = UNLOCKED,

    const UNLOCKED = 0;
    const LOCKED = 1;

    const Waiter = struct {
        // forced Waiter alignment to ensure it doesn't clash with LOCKED
        next: ?*Waiter align(2),
        tail: *Waiter,
        task: pike.Task,
    };

    pub fn initLocked() Mutex {
        return Mutex{ .head = LOCKED };
    }

    pub fn acquire(self: *Mutex) Held {
        const held = self.mutex.acquire();

        // self.head transitions from multiple stages depending on the value:
        // UNLOCKED -> LOCKED:
        //   acquire Mutex ownership when theres no waiters
        // LOCKED -> <Waiter head ptr>:
        //   Mutex is already owned, enqueue first Waiter
        // <head ptr> -> <head ptr>:
        //   Mutex is owned with pending waiters. Push our waiter to the queue.

        if (self.head == UNLOCKED) {
            self.head = LOCKED;
            held.release();
            return Held{ .lock = self };
        }

        var waiter: Waiter = undefined;
        waiter.next = null;
        waiter.tail = &waiter;

        const head = switch (self.head) {
            UNLOCKED => unreachable,
            LOCKED => null,
            else => @intToPtr(*Waiter, self.head),
        };

        if (head) |h| {
            h.tail.next = &waiter;
            h.tail = &waiter;
        } else {
            self.head = @ptrToInt(&waiter);
        }

        suspend {
            waiter.task = pike.Task.init(@frame());
            held.release();
        }

        return Held{ .lock = self };
    }

    pub const Held = struct {
        lock: *Mutex,

        pub fn release(self: Held) void {
            const waiter = blk: {
                const held = self.lock.mutex.acquire();
                defer held.release();

                // self.head goes through the reverse transition from acquire():
                // <head ptr> -> <new head ptr>:
                //   pop a waiter from the queue to give Mutex ownership when theres still others pending
                // <head ptr> -> LOCKED:
                //   pop the laster waiter from the queue, while also giving it lock ownership when awaken
                // LOCKED -> UNLOCKED:
                //   last lock owner releases lock while no one else is waiting for it

                switch (self.lock.head) {
                    UNLOCKED => unreachable, // Mutex unlocked while unlocking
                    LOCKED => {
                        self.lock.head = UNLOCKED;
                        break :blk null;
                    },
                    else => {
                        const waiter = @intToPtr(*Waiter, self.lock.head);
                        self.lock.head = if (waiter.next == null) LOCKED else @ptrToInt(waiter.next);
                        if (waiter.next) |next|
                            next.tail = waiter.tail;
                        break :blk waiter;
                    },
                }
            };

            if (waiter) |w| {
                pike.dispatch(&w.task, .{});
            }
        }
    };
};

// modified from: https://github.com/kprotty/zap/blob/ziggo/benches/http/http3.zig
pub fn Queue(comptime T: type, comptime buf_size: comptime_int) type {
    return struct {
        lock: std.Mutex = std.Mutex{},
        buffer: [buf_size]T = undefined,
        head: usize = 0,
        tail: usize = 0,
        closed: bool = false,
        readers: ?*Waiter = null,
        writers: ?*Waiter = null,

        const Self = @This();
        const T = @typeInfo([buf_size]T).Array.child;
        const Waiter = struct {
            next: ?*Waiter,
            tail: *Waiter,
            item: error{Closed}!T,
            task: zap.runtime.executor.Task,
        };

        pub fn close(self: *Self) void {
            const held = self.lock.acquire();

            if (self.closed) {
                held.release();
                return;
            }

            var readers = self.readers;
            var writers = self.writers;
            self.readers = null;
            self.writers = null;
            self.closed = true;
            held.release();

            var batch = zap.runtime.executor.Batch{};
            defer zap.runtime.schedule(batch, .{});

            while (readers) |waiter| {
                waiter.item = error.Closed;
                batch.push(&waiter.task);
                readers = waiter.next;
            }
            while (writers) |waiter| {
                waiter.item = error.Closed;
                batch.push(&waiter.task);
                writers = waiter.next;
            }
        }

        pub fn push(self: *Self, item: T) !void {
            const held = self.lock.acquire();

            if (self.closed) {
                held.release();
                return error.Closed;
            }

            if (self.readers) |reader| {
                const waiter = reader;
                self.readers = waiter.next;
                held.release();

                waiter.item = item;
                zap.runtime.schedule(&waiter.task, .{});
                return;
            }

            if (self.tail -% self.head < self.buffer.len) {
                self.buffer[self.tail % self.buffer.len] = item;
                self.tail +%= 1;
                held.release();
                return;
            }

            var waiter: Waiter = undefined;
            waiter.next = null;
            if (self.writers) |head| {
                head.tail.next = &waiter;
                head.tail = &waiter;
            } else {
                self.writers = &waiter;
                waiter.tail = &waiter;
            }

            suspend {
                waiter.item = item;
                waiter.task = @TypeOf(waiter.task).init(@frame());
                held.release();
            }

            _ = try waiter.item;
        }

        pub fn tryPop(self: *Self) !?T {
            const held = self.lock.acquire();

            if (self.writers) |writer| {
                const waiter = writer;
                self.writers = waiter.next;
                held.release();

                const item = writer.item catch unreachable;
                zap.runtime.schedule(&waiter.task, .{});
                return item;
            }

            if (self.tail != self.head) {
                const item = self.buffer[self.head % self.buffer.len];
                self.head +%= 1;
                held.release();
                return item;
            }

            const closed = self.closed;
            held.release();
            if (closed)
                return error.Closed;
            return null;
        }

        pub fn pop(self: *Self) !T {
            const held = self.lock.acquire();

            if (self.writers) |writer| {
                const waiter = writer;
                self.writers = waiter.next;
                held.release();

                const item = writer.item catch unreachable;
                zap.runtime.schedule(&waiter.task, .{});
                return item;
            }

            if (self.tail != self.head) {
                const item = self.buffer[self.head % self.buffer.len];
                self.head +%= 1;
                held.release();
                return item;
            }

            if (self.closed) {
                held.release();
                return error.Closed;
            }

            var waiter: Waiter = undefined;
            waiter.next = null;
            if (self.readers) |head| {
                head.tail.next = &waiter;
                head.tail = &waiter;
            } else {
                self.readers = &waiter;
                waiter.tail = &waiter;
            }

            suspend {
                waiter.item = undefined;
                waiter.task = @TypeOf(waiter.task).init(@frame());
                held.release();
            }

            return (try waiter.item);
        }
    };
}