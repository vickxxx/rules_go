package(
    default_visibility = ["//visibility:public"],
)

load("//go:def.bzl", "go_library", "go_binary")

go_library(
    name = "example_command_lib",
    srcs = ["main.go"],
    deps = [
        "//examples/cgo:go_default_library",
    ],
)

go_binary(
    name = "example_command",
    library = ":example_command_lib",
)

sh_test(
    name = "example_command_test",
    size = "small",
    srcs = ["example_command_test.sh"],
    data = [":example_command"],
)
