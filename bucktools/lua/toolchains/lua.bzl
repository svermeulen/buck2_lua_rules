
LuaToolchainInfo = provider(fields = [
    "lua_exe",
])

def _system_luajit_toolchain_impl(ctx):
    return [
        DefaultInfo(),
        LuaToolchainInfo(
            lua_exe = ctx.attrs._run_luajit,
        ),
    ]

system_luajit_toolchain = rule(
    impl = _system_luajit_toolchain_impl,
    attrs = {
        "_run_luajit": attrs.default_only(attrs.dep(providers = [RunInfo], default = "@root//third-party/lua/luajit:run_luajit")),
    },
    is_toolchain_rule = True,
)

