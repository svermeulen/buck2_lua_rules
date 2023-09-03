
load("//bucktools/lua:defs.bzl", "LuaLibraryInfo", "create_lua_library_info")
load("@prelude//:asserts.bzl", "asserts")

def _teal_library_impl(ctx: AnalysisContext):
    lua_files = []
    source_maps = {}

    for f in ctx.attrs.srcs:
        if f.short_path[-5:] == ".d.tl":
            continue

        if f.extension == ".lua":
            lua_files.append(f)
        else:
            asserts.equals(f.extension, ".tl")

            lua_short_path = f.short_path[:-len(f.extension)] + ".lua"
            lua_file = ctx.actions.declare_output(lua_short_path)

            run_args = cmd_args(ctx.attrs._run_teal[RunInfo])
            run_args.add("gen")
            run_args.add(f)
            run_args.add("-o")
            run_args.add(lua_file.as_output())

            ctx.actions.run(run_args, category = "teal", identifier = f.short_path)

            lua_files.append(lua_file)

            source_maps[lua_short_path] = f

    lib_info = create_lua_library_info(
        ctx,
        lua_files,
        deps = ctx.attrs.deps,
        source_maps = source_maps,
    )

    manifest_info = lib_info.manifests.value.srcs

    return [
        # We aren't really using DefaultInfo for anything atm
        # But seems to make sense to have it include the manifest and the artifacts
        DefaultInfo(
            default_output = manifest_info.manifest,
            other_outputs = [x for x, _ in manifest_info.artifacts]),
        lib_info,
    ]

teal_library = rule(impl = _teal_library_impl, attrs = {
    "srcs": attrs.named_set(attrs.source(), sorted = True, default = []),
    "deps": attrs.list(attrs.dep(providers = [LuaLibraryInfo]), default = []),
    "_run_teal": attrs.default_only(attrs.dep(providers = [RunInfo], default = "//third-party/lua/tl:tl_run")),
})

