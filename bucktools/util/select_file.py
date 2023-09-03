
import argparse
from dataclasses import dataclass
from pathlib import Path
import logging
import os
from typing import List, Optional

@dataclass
class CommandLineArgs:
    input_paths: List[Path]
    filter: Optional[str]
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
        '--filter',
        type=str)

    parser.add_argument(
        '--output',
        type=str)

    raw_args = parser.parse_args()

    input_paths = [git_root.joinpath(x) for x in sum([x for x in raw_args.input_path], [])]
    filter = raw_args.filter
    output_path = git_root.joinpath(raw_args.output)

    return CommandLineArgs(
        input_paths=input_paths,
        filter=filter,
        output_path=output_path)

def _main_impl():
    git_root = Path.cwd()
    args = _parse_args(git_root)
    logging.debug(f"Received command line args: {repr(args)}")

    for path in args.input_paths:
        assert path.exists(), f"Input path '{path}' does not exist"
        
    assert not args.output_path.exists(), f"Output path '{args.output_path}' already exists"

    matches = []

    if args.filter is None:
        assert len(args.input_paths) == 1, "Expected to only match one path when no filter is specified"

        matches.append(args.input_paths[0])
    else:
        for path in args.input_paths:
            logging.debug(f"Processing input path '{path}'")

            if path.match(args.filter):
                matches.append(path)
                continue

            if path.is_dir():
                matches.extend(path.rglob(args.filter))

        assert len(matches) == 1, f"Found {len(matches)} matches but expected one for filter '{args.filter}'"

    args.output_path.parent.mkdir(parents=True, exist_ok=True)

    os.symlink(matches[0], args.output_path)

    logging.debug(f"Successfully output new sym link")

def main():
    try:
        _main_impl()
    except Exception as e:
        logging.error("Failure with file_selector.py: " + str(e))
        raise 

main()

