
load("@prelude//utils:utils.bzl", "from_named_set")
load("@prelude//utils:arglike.bzl", "ArgLike")  # @unused Used as a type
load("@prelude//:asserts.bzl", "asserts")
load("@prelude//decls:common.bzl", "buck")

LuaManifestInfo = record(
    # The actual manifest file (in the form of a JSON file).
    manifest = field(Artifact),
    # All artifacts that are referenced in the manifest.
    artifacts = field(list[[Artifact, ArgLike]]),
)

LuaLibraryManifests = record(
    label = field(Label),
    srcs = field([LuaManifestInfo.type, None]),
)

def _source_artifacts(value: LuaLibraryManifests.type):
    if value.srcs == None:
        return []
    return [a for a, _ in value.srcs.artifacts]

def _source_manifests(value: LuaLibraryManifests.type):
    if value.srcs == None:
        return []
    return value.srcs.manifest

LuaLibraryManifestsTSet = transitive_set(
    args_projections = {
        "source_manifests": _source_manifests,
        "source_artifacts": _source_artifacts,
    },
)

LuaLibraryInfo = provider(fields = [
    "manifests",  # LuaLibraryManifestsTSet
])

def _write_manifest(
        ctx: AnalysisContext,
        name: str,
        entries) -> Artifact:
    """
    Serialize the given source manifest entries to a JSON file.
    """
    return ctx.actions.write_json(name + ".manifest", entries)

def _create_manifest_for_entries(
        ctx: AnalysisContext,
        name: str,
        entries) -> LuaManifestInfo.type:
    """
    Generate a source manifest for the given list of sources.
    """
    return LuaManifestInfo(
        manifest = _write_manifest(ctx, name, entries),
        artifacts = [(a, dest) for dest, a, _, _ in entries],
    )

def _create_manifest_for_source_map(
        ctx: AnalysisContext,
        param: str,
        srcs: dict[str, Artifact],
        source_maps,
) -> LuaManifestInfo.type:
    """
    Generate a source manifest for the given map of sources from the given rule.
    """
    origin = "{} {}".format(ctx.label.raw_target(), param)
    return _create_manifest_for_entries(
        ctx,
        param,
        [(dest, artifact, origin, source_maps.get(dest, None)) for dest, artifact in srcs.items()],
    )

def create_lua_library_info(
        ctx: AnalysisContext,
        srcs = None,
        deps = [],
        import_directory = None,
        import_namespace = None,
        source_maps = None,
    ):

    if source_maps == None:
        source_maps = {}

    srcs = from_named_set(srcs)

    if import_directory != None:
        import_directory = import_directory + "/"
        new_srcs = {}

        for k, v in srcs.items():
            if k.startswith(import_directory):
                new_srcs[k[len(import_directory):]] = v
            else:
                fail("Expected source {} to start with prefix {}".format(k, import_directory))

        srcs = new_srcs

    if import_namespace != None:
        asserts.true(not import_namespace.endswith("/"))
        asserts.true(not import_namespace.endswith("\\"))
        import_namespace = import_namespace + "/"

        new_srcs = {}

        for k, v in srcs.items():
            new_srcs[import_namespace + k] = v

        srcs = new_srcs

    src_manifest = _create_manifest_for_source_map(ctx, "srcs", srcs, source_maps)

    deps = _gather_dep_libraries(deps)

    manifests = LuaLibraryManifests(
        label = ctx.label,
        srcs = src_manifest,
    )

    return LuaLibraryInfo(
        manifests = ctx.actions.tset(LuaLibraryManifestsTSet, value = manifests, children = [dep.manifests for dep in deps]),
    )


def _gather_dep_libraries(raw_deps: list[Dependency]) -> list[LuaLibraryInfo.type]:
    deps = []
    for dep in raw_deps:
        if LuaLibraryInfo in dep:
            deps.append(dep[LuaLibraryInfo])
        else:
            fail("Dependency {} is not a lua_library".format(dep.label))
    return deps

def _lua_library_impl(ctx: AnalysisContext):
    lib_info = create_lua_library_info(
        ctx,
        ctx.attrs.srcs,
        deps = ctx.attrs.deps,
        import_directory = ctx.attrs.import_directory,
        import_namespace = ctx.attrs.import_namespace,
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

def create_linktree_dir(
    ctx: AnalysisContext,
    deps: list[Dependency],
    srcs: list[Artifact],
    extra_args = None,
):
    lib_info = create_lua_library_info(
        ctx,
        srcs = srcs,
        deps = deps,
    )

    linktree_dir = ctx.actions.declare_output("{}-linktree".format(ctx.attrs.name), dir = True)

    create_linktree_args = cmd_args(ctx.attrs._linktree_generator[RunInfo])
    create_linktree_args.add(linktree_dir.as_output())
    create_linktree_args.hidden(lib_info.manifests.project_as_args("source_artifacts"))
    create_linktree_args.add(cmd_args(lib_info.manifests.project_as_args("source_manifests"), format = "--module-manifest={}"))

    if extra_args != None:
        create_linktree_args.add(extra_args)

    ctx.actions.run(create_linktree_args, category = "lua", identifier = "bootstrap")
    return linktree_dir

def _lua_binary_impl(ctx: AnalysisContext):
    linktree_dir = create_linktree_dir(
        ctx, 
        deps=ctx.attrs.deps,
        srcs=ctx.attrs.srcs)

    bootstrap_lua = "require(\"{}\")".format(ctx.attrs.main)
    bootstrap_lua_file = ctx.actions.declare_output("_bootstrap.lua")
    ctx.actions.write(bootstrap_lua_file, bootstrap_lua)

    run_args = cmd_args(ctx.attrs._run_lua[RunInfo])
    run_args.add("--linktreedir")
    run_args.add(linktree_dir)
    run_args.add(bootstrap_lua_file)
    run_args.add("--")

    argsfile_name = ctx.attrs.name + ".argsfile"
    argsfile = ctx.actions.declare_output(argsfile_name)
    ctx.actions.write(argsfile, run_args, allow_args = True, absolute = True)

    python_runner_name = ctx.attrs.name + "_run.py"
    python_runner = ctx.actions.declare_output(python_runner_name)
    ctx.actions.write(python_runner, """
import argparse
from pathlib import Path
import logging
import subprocess
import sys
from typing import Tuple, List

def _parse_args(git_root:Path) -> Tuple[Path, List[str]]:
    parser = argparse.ArgumentParser(description='run_from_argsfile.py')

    parser.add_argument(
        'argsfile',
        type=str)

    argsfile = sys.argv[1]

    assert sys.argv[2] == "--"
    extra_args = sys.argv[3:]

    assert argsfile is not None and len(argsfile) > 0
    return git_root.joinpath(argsfile), extra_args

def _main_impl():
    git_root = Path.cwd()

    # Uncomment for debugging
    # log_path = Path(<insert path to temporary log file>)
    # logging.basicConfig(filename=log_path, level=logging.DEBUG)

    argsfile, extra_args = _parse_args(git_root)

    logging.debug(f"Loading args file '{argsfile}'")

    run_args = []

    for arg in argsfile.read_text().splitlines():
        run_args.append(arg)

    logging.debug(f"Running with args: {repr(run_args)}")
    result = subprocess.run(run_args + extra_args)

    if result.returncode == 0:
        logging.debug(f"Successfully executed from given args file")
    else:
        logging.debug(f"Failed to execute from given args file")
        exit(result.returncode)

def main():
    try:
        _main_impl()
    except Exception as e:
        logging.error("Failure with file_selector.py: " + str(e))
        raise 

main()
""")

    run_bash_script = ctx.actions.declare_output(ctx.attrs.name + ".sh")
    ctx.actions.write(run_bash_script, "#!/bin/bash\npython3 `dirname $BASH_SOURCE`/{0} `dirname $BASH_SOURCE`/{1} -- \"$@\"\n".format(python_runner_name, argsfile_name), is_executable = True)

    run_batch_script = ctx.actions.declare_output(ctx.attrs.name + ".bat")
    ctx.actions.write(run_batch_script, "@echo off\nset SCRIPT_DIR=%~dp0\npython %SCRIPT_DIR%\\{0} %SCRIPT_DIR%\\{1} -- %*".format(python_runner_name, argsfile_name), is_executable = True)

    return [
        DefaultInfo(
            default_output = None,
            other_outputs = [linktree_dir, bootstrap_lua_file, python_runner, run_batch_script, run_bash_script, argsfile]),
        RunInfo(run_args),
    ]

lua_library = rule(impl = _lua_library_impl, attrs = {
    "srcs": attrs.named_set(attrs.source(), sorted = True, default = []),
    "deps": attrs.list(attrs.dep(providers = [LuaLibraryInfo]), default = []),
    "import_directory": attrs.option(attrs.string(), default = None),
    "import_namespace": attrs.option(attrs.string(), default = None),
})

def lua_binary_hidden_args():
    return {
        "_linktree_generator": attrs.default_only(attrs.dep(providers = [RunInfo], default = "//bucktools/lua/tools:make_lua_linktree_dir")),
        "_run_lua": attrs.default_only(attrs.dep(providers = [RunInfo], default = "//third-party/lua/luajit:run_luajit")),
    }

lua_binary = rule(impl = _lua_binary_impl, attrs = (
        {
            "main": attrs.string(),
            "srcs": attrs.named_set(attrs.source(), sorted = True, default = []),
            "deps": attrs.list(attrs.dep(providers = [LuaLibraryInfo]), default = []),
        } | 
        lua_binary_hidden_args()
    )
)

