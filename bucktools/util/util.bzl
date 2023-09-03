
def _select_files(ctx: AnalysisContext):
    output_path = ctx.actions.declare_output(ctx.attrs.out, dir = True)

    run_args = cmd_args(ctx.attrs._runner[RunInfo])
    run_args.add("--input-path")
    run_args.add(ctx.attrs.srcs)
    run_args.add("--filter")
    run_args.add(ctx.attrs.filter)
    run_args.add("--strip-prefix")
    run_args.add(ctx.attrs.strip_prefix)
    run_args.add("--output")
    run_args.add(output_path.as_output())

    ctx.actions.run(run_args, category = "file_select")

    return [
        DefaultInfo(default_output = output_path),
    ]

select_files = rule(impl = _select_files, attrs = {
    "srcs": attrs.named_set(attrs.source(), sorted = True, default = []),
    "filter": attrs.string(),
    "strip_prefix": attrs.string(),
    "out": attrs.string(),
    "_runner": attrs.default_only(attrs.dep(providers = [RunInfo], default = "//bucktools/util:select_files")),
})

def _select_file(ctx: AnalysisContext):
    output_path = ctx.actions.declare_output(ctx.attrs.out)

    run_args = cmd_args(ctx.attrs._runner[RunInfo])
    run_args.add("--input-path")
    run_args.add(ctx.attrs.srcs)

    if ctx.attrs.filter != None:
        run_args.add("--filter")
        run_args.add(ctx.attrs.filter)

    run_args.add("--output")
    run_args.add(output_path.as_output())

    ctx.actions.run(run_args, category = "file_select")

    return [
        DefaultInfo(default_output = output_path),
    ]

select_file = rule(impl = _select_file, attrs = {
    "srcs": attrs.named_set(attrs.source(), sorted = True, default = []),
    "filter": attrs.option(attrs.string(), default = None),
    "out": attrs.string(),
    "_runner": attrs.default_only(attrs.dep(providers = [RunInfo], default = "//bucktools/util:select_file")),
})


