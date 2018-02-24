config_setting(
    name = "darwin",
    values = {"cpu": "darwin"},
)

cc_library(
    name = "version",
    srcs = ["cxx_version.cc"],
    hdrs = ["version.h"],
    linkopts = ["-ldl"],
    visibility = ["//examples/cgo:__pkg__"],
    # TODO(yugui) Support darwin too and remove this workaround.
    # See also comments in cxx_version.cc.
    deps = select({
        ":darwin": [],
        "//conditions:default": [":c_version"],
    }),
)

cc_library(
    name = "c_version",
    srcs = ["c_version.c"],
    hdrs = ["c_version.h"],
)
