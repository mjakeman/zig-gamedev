const std = @import("std");
const Builder = std.build.Builder;
const Pkg = std.build.Pkg;

fn makeDxcCmd(
    comptime input_path: []const u8,
    comptime entry_point: []const u8,
    comptime output_filename: []const u8,
    comptime profile: []const u8,
    comptime define: []const u8,
) [9][]const u8 {
    const shader_ver = "6_6";
    const shader_dir = "content/shaders/";
    return [9][]const u8{
        "../../external/bin/dxc/dxc.exe",
        input_path,
        "/E " ++ entry_point,
        "/Fo " ++ shader_dir ++ output_filename,
        "/T " ++ profile ++ "_" ++ shader_ver,
        if (define.len == 0) "" else "/D " ++ define,
        "/WX",
        "/Ges",
        "/O3",
    };
}

pub fn build(b: *std.build.Builder) void {
    const enable_pix = b.option(bool, "enable-pix", "Enable PIX GPU events and markers") orelse false;
    const enable_dx_debug = b.option(
        bool,
        "enable-dx-debug",
        "Enable debug layer for D3D12, D2D1, DirectML and DXGI",
    ) orelse false;
    const enable_dx_gpu_debug = b.option(
        bool,
        "enable-dx-gpu-debug",
        "Enable GPU-based validation for D3D12",
    ) orelse false;
    const tracy = b.option([]const u8, "tracy", "Enable Tracy profiler integration (supply path to Tracy source)");

    const exe_options = b.addOptions();
    exe_options.addOption(bool, "enable_pix", enable_pix);
    exe_options.addOption(bool, "enable_dx_debug", enable_dx_debug);
    exe_options.addOption(bool, "enable_dx_gpu_debug", enable_dx_gpu_debug);
    exe_options.addOption(bool, "enable_tracy", tracy != null);

    b.installFile("../../external/bin/d3d12/D3D12Core.dll", "bin/d3d12/D3D12Core.dll");
    b.installFile("../../external/bin/d3d12/D3D12Core.pdb", "bin/d3d12/D3D12Core.pdb");
    b.installFile("../../external/bin/d3d12/D3D12SDKLayers.dll", "bin/d3d12/D3D12SDKLayers.dll");
    b.installFile("../../external/bin/d3d12/D3D12SDKLayers.pdb", "bin/d3d12/D3D12SDKLayers.pdb");
    const install_content_step = b.addInstallDirectory(
        .{ .source_dir = "content", .install_dir = .{ .custom = "" }, .install_subdir = "bin/content" },
    );
    b.getInstallStep().dependOn(&install_content_step.step);

    const dxc_step = b.step("dxc", "Build shaders");

    var dxc_command = makeDxcCmd("../../libs/common/common.hlsl", "vsImGui", "imgui.vs.cso", "vs", "PSO__IMGUI");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("../../libs/common/common.hlsl", "psImGui", "imgui.ps.cso", "ps", "PSO__IMGUI");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/rasterization.hlsl", "vsRecordPixels", "record_pixels.vs.cso", "vs", "PSO__RECORD_PIXELS");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/rasterization.hlsl", "psRecordPixels", "record_pixels.ps.cso", "ps", "PSO__RECORD_PIXELS");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/rasterization.hlsl", "vsDrawMesh", "draw_mesh.vs.cso", "vs", "PSO__DRAW_MESH");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/rasterization.hlsl", "psDrawMesh", "draw_mesh.ps.cso", "ps", "PSO__DRAW_MESH");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/rasterization.hlsl", "csDrawPixels", "draw_pixels.cs.cso", "cs", "PSO__DRAW_PIXELS");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/rasterization.hlsl", "csClearPixels", "clear_pixels.cs.cso", "cs", "PSO__CLEAR_PIXELS");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd(
        "../../libs/common/common.hlsl",
        "csGenerateMipmaps",
        "generate_mipmaps.cs.cso",
        "cs",
        "PSO__GENERATE_MIPMAPS",
    );
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    install_content_step.step.dependOn(dxc_step);

    const exe = b.addExecutable("rasterization", "src/rasterization.zig");
    const target_options = b.standardTargetOptions(.{});
    const release_options = b.standardReleaseOptions();

    exe.setBuildMode(release_options);
    exe.setTarget(target_options);
    exe.addOptions("build_options", exe_options);

    if (tracy) |tracy_path| {
        const client_cpp = std.fs.path.join(
            b.allocator,
            &[_][]const u8{ tracy_path, "TracyClient.cpp" },
        ) catch unreachable;
        exe.addIncludeDir(tracy_path);
        exe.addCSourceFile(client_cpp, &[_][]const u8{
            "-DTRACY_ENABLE=1",
            "-fno-sanitize=undefined",
            "-D_WIN32_WINNT=0x601",
        });
        exe.linkSystemLibrary("ws2_32");
        exe.linkSystemLibrary("dbghelp");
    }

    // This is needed to export symbols from an .exe file.
    // We export D3D12SDKVersion and D3D12SDKPath symbols which
    // is required by DirectX 12 Agility SDK.
    exe.rdynamic = true;
    exe.want_lto = false;

    const pkg_win32 = Pkg{
        .name = "win32",
        .path = .{ .path = "../../libs/win32/win32.zig" },
    };
    exe.addPackage(pkg_win32);

    const pkg_common = Pkg{
        .name = "common",
        .path = .{ .path = "../../libs/common/common.zig" },
        .dependencies = &[_]Pkg{
            Pkg{
                .name = "win32",
                .path = .{ .path = "../../libs/win32/win32.zig" },
                .dependencies = null,
            },
            Pkg{
                .name = "build_options",
                .path = exe_options.getSource(),
                .dependencies = null,
            },
        },
    };
    exe.addPackage(pkg_common);

    const external = "../../external/src";
    exe.addIncludeDir(external);

    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("c++");
    exe.linkSystemLibrary("imm32");

    exe.addCSourceFile(external ++ "/imgui/imgui.cpp", &[_][]const u8{""});
    exe.addCSourceFile(external ++ "/imgui/imgui_widgets.cpp", &[_][]const u8{""});
    exe.addCSourceFile(external ++ "/imgui/imgui_tables.cpp", &[_][]const u8{""});
    exe.addCSourceFile(external ++ "/imgui/imgui_draw.cpp", &[_][]const u8{""});
    exe.addCSourceFile(external ++ "/imgui/imgui_demo.cpp", &[_][]const u8{""});
    exe.addCSourceFile(external ++ "/cimgui.cpp", &[_][]const u8{""});

    exe.addCSourceFile(external ++ "/cgltf.c", &[_][]const u8{""});

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}