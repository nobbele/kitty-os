const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const Target = std.Target.x86;
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
        // We use software float because we are disabling all SIMD stuff
        .cpu_features_add = Target.featureSet(&.{.soft_float}),
        // Disable all SIMD related stuff because SIMD are problematic in kernel
        .cpu_features_sub = Target.featureSet(&.{ .avx, .avx2, .sse, .sse2, .mmx }),
    });

    const kernel = b.addExecutable(.{
        .name = "KittyOS.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .code_model = .kernel,

            .red_zone = false,
        }),
    });
    kernel.setLinkerScript(b.path("src/linker.ld"));
    b.installArtifact(kernel);

    const kernel_check = b.addExecutable(.{
        .name = "KittyOS.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .code_model = .kernel,

            .red_zone = false,
        }),
    });
    const check = b.step("check", "Check if foo compiles");
    check.dependOn(&kernel_check.step);

    // == Make ISO ==
    const iso_wf = b.addWriteFiles();
    _ = iso_wf.addCopyFile(b.path("limine/limine-bios-cd.bin"), "limine-bios-cd.bin");
    _ = iso_wf.addCopyFile(b.path("limine/limine-bios.sys"), "limine-bios.sys");
    _ = iso_wf.addCopyFile(b.path("limine/limine.conf"), "limine.conf");
    _ = iso_wf.addCopyFile(kernel.getEmittedBin(), "KittyOS.elf");
    _ = iso_wf.addCopyFile(b.path("program"), "program");
    iso_wf.step.dependOn(&kernel.step);

    const xorriso = b.addSystemCommand(&.{
        // zig fmt: off
        "xorriso",
        "-as", "mkisofs",
        "-b", "limine-bios-cd.bin", 
        "-no-emul-boot",
        "-boot-load-size", "4",                 
        "-boot-info-table", 
    });
    // zig fmt: on
    xorriso.addDirectoryArg(iso_wf.getDirectory());
    xorriso.addArgs(&.{ "-o", "KittyOS.iso" });
    xorriso.step.dependOn(&iso_wf.step);

    const make_iso_step = b.step("make-iso", "Create a bootable ISO image");
    make_iso_step.dependOn(&xorriso.step);

    const enable_debugger = b.option(bool, "debugger", "Enable debugger mode in QEMU") orelse false;

    const qemu = b.addSystemCommand(&.{
        // zig fmt: off
        "qemu-system-i386",
        "-cpu", "pentium2",
        "-m",   "128M",
        "-cdrom", "KittyOS.iso",
        "-boot", "d",
        "-no-reboot",
        "-no-shutdown",
        // "-d", "int",
        // "-s", "-S",
        // "-serial", "stdio",
    });
    
    if (enable_debugger) {
        qemu.addArgs(&.{"-s", "-S"});
    }
    // zig fmt: on
    qemu.step.dependOn(make_iso_step);

    const run_step = b.step("run", "Boot KittyOS in QEMU");
    run_step.dependOn(&qemu.step);
}
