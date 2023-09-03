
import argparse
from dataclasses import dataclass
from pathlib import Path
import logging
import os
from typing import List

@dataclass
class CommandLineArgs:
    input_paths: List[Path]
    filter: str
    strip_prefix: str
    output_path: Path

def _parse_args(git_root:Path) -> CommandLineArgs:
    parser = argparse.ArgumentParser(description='run_luajit')

    parser.add_argument(
        "--input-path",
        action="append",
        nargs="+",
        default=[],
        help="The list of input paths to process",
    )

    parser.add_argument(
        '--strip-prefix',
        type=str)

    parser.add_argument(
        '--filter',
        type=str)

    parser.add_argument(
        '--output',
        type=str)

    raw_args = parser.parse_args()

    input_paths = [git_root.joinpath(x) for x in sum([x for x in raw_args.input_path], [])]
    output_path = git_root.joinpath(raw_args.output)

    return CommandLineArgs(
        input_paths=input_paths,
        filter=raw_args.filter,
        strip_prefix=raw_args.strip_prefix,
        output_path=output_path)

def _main_impl():
    git_root = Path.cwd()
    args = _parse_args(git_root)
    logging.debug(f"Received command line args: {repr(args)}")

    for path in args.input_paths:
        assert path.exists(), f"Input path '{path}' does not exist"
        
    assert not args.output_path.exists(), f"Output path '{args.output_path}' already exists"

    matches = {}

    for path in args.input_paths:
        logging.debug(f"Processing input path '{path}'")

        if path.match(args.filter):
            assert path.name not in matches
            matches[path.name] = path
            continue

        if path.is_dir():
            for sub_match in path.rglob(args.filter):
                relative_path = str(sub_match.relative_to(path))
                assert relative_path not in matches
                matches[relative_path] = sub_match

    args.output_path.mkdir(parents=False, exist_ok=False)

    for relative_path, path in matches.items():
        if args.strip_prefix is not None:
            assert relative_path.startswith(args.strip_prefix)
            relative_path = relative_path[len(args.strip_prefix):]
            assert not relative_path.startswith("/") and not relative_path.startswith("\\")

        new_path = args.output_path.joinpath(relative_path)
        new_path.parent.mkdir(parents=True, exist_ok=True)
        assert not new_path.exists(), f"Expected new path '{new_path}' to not exist"
        os.symlink(path, new_path)

    logging.debug(f"Successfully output new sym link")

def main():
    try:
        _main_impl()
    except Exception as e:
        logging.error("Failure with file_selector.py: " + str(e))
        raise 

main()

