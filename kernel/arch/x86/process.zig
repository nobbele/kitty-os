const root = @import("root");

pub fn startTask(task: *root.process.Task) noreturn {
    root.scheduler.switchTo(task);
    asm volatile (
        \\ mov %[ds], %%ds
        \\ mov %[ds], %%es
        \\ mov %[ds], %%fs
        \\ mov %[ds], %%gs
        \\
        \\ pushl %[ds] # ss
        \\ pushl %[esp]
        \\ pushl %[flags]
        \\ pushl %[cs]
        \\ pushl %[eip]
        \\ iret
        :
        : [ds] "r" (@as(u32, root.USER_DS)),
          [esp] "r" (task.frame.esp),
          [flags] "r" (task.frame.flags),
          [cs] "i" (root.USER_CS),
          [eip] "r" (task.frame.eip),
        : .{ .memory = true });
    unreachable;
}
