
from typing import List, cast, Optional
import argparse
from dataclasses import dataclass
from pathlib import Path
import os
import shutil
import logging
import json
import errno
import time

@dataclass
class CommandLineArgs:
    module_manifests: List[Path]
    skip_paths: List[str]
    output_dir: Path
    namespace: Optional[str]
    create_runtime_build_info_loader:bool

@dataclass
class ModuleInfo:
    import_path:str
    file_path:Path
    buck_target:str
    source_path:Optional[Path]

def _parse_args(git_root:Path) -> CommandLineArgs:
    parser = argparse.ArgumentParser(description='make_lua_linktree_dir')

    parser.add_argument(
        "-m",
        "--module-manifest",
        metavar="MANIFESTS",
        action="append",
        nargs="+",
        default=[],
        help="The list of manifests to link",
    )

    parser.add_argument(
        "-i",
        "--skip-paths",
        metavar="SKIP_PATHS",
        action="append",
        nargs="+",
        default=[],
        help="The list of paths to skip",
    )

    parser.add_argument("--namespace", type=str, default=None)

    parser.add_argument('output_dir', type=str)

    parser.add_argument("--create-runtime-build-info-loader", action="store_true")

    raw_args = parser.parse_args()

    module_manifests = [git_root.joinpath(x) for x in sum([x for x in raw_args.module_manifest], [])]
    skip_paths = [x for x in sum([x for x in raw_args.skip_paths], [])]
    output_dir = git_root.joinpath(raw_args.output_dir)

    return CommandLineArgs(
        namespace=raw_args.namespace,
        skip_paths=skip_paths,
        create_runtime_build_info_loader=raw_args.create_runtime_build_info_loader,
        module_manifests=module_manifests,
        output_dir=output_dir)

def _lexists(path: Path) -> bool:
    """
    Like `Path.exists()` but works on dangling. symlinks
    """

    try:
        path.lstat()
    except FileNotFoundError:
        return False
    except OSError as e:
        if e.errno == errno.ENOENT:
            return False
        raise
    return True

def _add_sym_link(real_path:Path, link_path:Path):
    logging.debug(f"Creating sym link at '{link_path}' pointing to '{real_path}'")

    try:
        os.symlink(real_path, link_path)

        # Use this instead if you suspect that sym links might be causing problems
        # Using sym links is much faster though, esp. on windows
        # shutil.copy(real_path, link_path)
    except OSError:
        if _lexists(link_path):
            if os.path.islink(link_path):
                raise ValueError(
                    "{} already exists, and is linked to {}. Cannot link to {}".format(
                        link_path, os.readlink(link_path), real_path
                    )
                )
            else:
                raise ValueError(
                    "{} already exists. Cannot link to {}".format(link_path, real_path)
                )
        else:
            raise

def _generate_build_info_lua(module_infos:List[ModuleInfo]) -> str:
    def serialize_path(path:Path) -> str:
        return str(path).replace("\\", "\\\\")
        
    result = f"""

local build_info = {{
  ["build_time"] = {time.time()},
  ["manifest"] = {{"""

    for item in module_infos:
        result += f"""
    ["{item.import_path}"] = {{
      ["path"] = "{serialize_path(item.file_path)}",
      ["source"] = {'"' + serialize_path(item.source_path) + '"' if item.source_path is not None else 'nil'},
    }},"""

    result += """
  },
}

return function()
  return build_info
end
"""
    return result

def main():
    git_root = Path.cwd()
    args = _parse_args(git_root)

    if args.namespace is not None:
        assert not args.namespace.endswith("/") and not args.namespace.endswith("\\")

    args.output_dir.mkdir(parents=False, exist_ok=False)

    # Uncomment for debugging
    # log_path = args.output_dir.joinpath("_make_lua_linktree_dir.py.log")
    # logging.basicConfig(filename=log_path, level=logging.DEBUG)

    logging.debug(f"Received command line args: {repr(args)}")

    linktree_dir = args.output_dir
    module_infos:List[ModuleInfo] = []

    def import_path_to_full_path(import_path:str) -> Path:
        result = linktree_dir

        if args.namespace is not None:
            result = result.joinpath(args.namespace)

        return result.joinpath(import_path)

    for manifest in args.module_manifests:
        file_infos = json.load(manifest.open())
        for info in file_infos:
            import_path = cast(str, info[0])

            if import_path in args.skip_paths:
                logging.debug(f"Skipping path '{import_path}'")
                continue

            file_path = git_root.joinpath(info[1])

            link_path = import_path_to_full_path(import_path)

            link_path.parent.mkdir(parents=True, exist_ok=True)
            logging.debug(f"Adding sym link at relative path '{import_path}', file_path = '{file_path}', link_path = '{link_path}'")
            _add_sym_link(file_path, link_path)

            source_path = None

            if len(info) > 3 and info[3] is not None:
                source_path = git_root.joinpath(info[3])

            module_info = ModuleInfo(
                import_path=import_path,
                file_path=link_path,
                buck_target=info[2],
                source_path=source_path)
            module_infos.append(module_info)

    build_info_path = import_path_to_full_path("build_info_provider.lua")
    build_info_path.write_text(_generate_build_info_lua(module_infos))

    logging.debug(f"Completed successfully")

main()

