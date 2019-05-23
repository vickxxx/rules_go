# Copyright 2014 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("//go/private:go_repository.bzl", "go_repository")

_REPOSITORY_TOOL_DEPS = {
    "buildtools": struct(
        importpath = "github.com/bazelbuild/buildtools",
        repo = "https://github.com/bazelbuild/buildtools",
        sha256 = "efa3978c6e8ed8aae713943017d2c8d559a9c8a6de0239f0972e0a18cde92e64",
        commit = "d5dcc29f2304aa28c29ecb8337d52bb9de908e0c",
    ),
    "tools": struct(
        importpath = "golang.org/x/tools",
        repo = "https://github.com/golang/tools",
        sha256 = "e4b020492a6b97c006473c1bdb03bb719e0558047609126123acdfb20d2c1acf",
        commit = "3d92dd60033c312e3ae7cac319c792271cf67e37",
    ),
}

def go_internal_tools_deps():
    """only for internal use in rules_go"""
    go_repository(
        name = "com_github_bazelbuild_buildtools",
        commit = _REPOSITORY_TOOL_DEPS["buildtools"].commit,
        sha256 = _REPOSITORY_TOOL_DEPS["buildtools"].sha256,
        importpath = _REPOSITORY_TOOL_DEPS["buildtools"].importpath,
    )
    go_repository(
        name = "org_golang_x_tools",
        commit = _REPOSITORY_TOOL_DEPS["tools"].commit,
        sha256 = _REPOSITORY_TOOL_DEPS["tools"].sha256,
        importpath = _REPOSITORY_TOOL_DEPS["tools"].importpath,
    )

def _fetch_repository_tools_deps(ctx, goroot, gopath):
    for name, dep in _REPOSITORY_TOOL_DEPS.items():
        result = ctx.execute(["mkdir", "-p", ctx.path("src/" + dep.importpath)])
        if result.return_code:
            fail("failed to create directory: %s" % result.stderr)
        archive = name + ".tar.gz"
        ctx.download_and_extract(
            url = "%s/archive/%s.tar.gz" % (dep.repo, dep.commit),
            output = "src/%s" % dep.importpath,
            stripPrefix = "%s-%s" % (name, dep.commit),
            sha256 = dep.sha256,
        )

    result = ctx.execute([
        "env",
        "GOROOT=%s" % goroot,
        "GOPATH=%s" % gopath,
        "PATH=%s/bin" % goroot,
        "go",
        "generate",
        "github.com/bazelbuild/buildtools/build",
    ])
    if result.return_code:
        fail("failed to go generate: %s" % result.stderr)

_GO_REPOSITORY_TOOLS_BUILD_FILE = """package(default_visibility = ["//visibility:public"])

filegroup(
    name = "fetch_repo",
    srcs = ["bin/fetch_repo"],
)

filegroup(
    name = "gazelle",
    srcs = ["bin/gazelle"],
)
"""

def _go_repository_tools_impl(ctx):
    go_tool = ctx.path(ctx.attr._go_tool)
    goroot = go_tool.dirname.dirname
    gopath = ctx.path("")
    prefix = "github.com/bazelbuild/rules_go/" + ctx.attr._tools.package
    src_path = ctx.path(ctx.attr._tools).dirname

    _fetch_repository_tools_deps(ctx, goroot, gopath)

    for t, pkg in [("gazelle", "gazelle/gazelle"), ("fetch_repo", "fetch_repo")]:
        ctx.symlink("%s/%s" % (src_path, t), "src/%s/%s" % (prefix, t))

        result = ctx.execute([
            "env",
            "GOROOT=%s" % goroot,
            "GOPATH=%s" % gopath,
            go_tool,
            "build",
            "-o",
            ctx.path("bin/" + t),
            "%s/%s" % (prefix, pkg),
        ])
        if result.return_code:
            fail("failed to build %s: %s" % (t, result.stderr))
    ctx.file("BUILD.bazel", _GO_REPOSITORY_TOOLS_BUILD_FILE, False)

_go_repository_tools = repository_rule(
    _go_repository_tools_impl,
    attrs = {
        "_tools": attr.label(
            default = Label("//go/tools:BUILD"),
            allow_files = True,
            single_file = True,
        ),
        "_go_tool": attr.label(
            default = Label("@io_bazel_rules_go_toolchain//:bin/go"),
            allow_files = True,
            single_file = True,
        ),
    },
)

_GO_TOOLCHAIN_BUILD_FILE = """load("@io_bazel_rules_go//go/private:go_root.bzl", "go_root")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "toolchain",
    srcs = glob(["bin/*", "pkg/**",]),
)

filegroup(
    name = "go_tool",
    srcs = ["bin/go"],
)

filegroup(
    name = "go_src",
    srcs = glob(["src/**"]),
)

filegroup(
    name = "go_include",
    srcs = ["pkg/include"],
)

go_root(
    name = "go_root",
    path = "{goroot}",
)
"""

def _check_bazel_version():
    version = native.bazel_version
    if not version.startswith("0.18.") and not version.startswith("0.17."):
        fail("Bazel version %s installed on your machine is not supported " +
             "by the current Bazel toolchain. Please re-install Bazel " +
             "version 0.18.1 from " +
             "https://github.com/bazelbuild/bazel/releases/tag/0.18.1" %
             version)
    print("Building with Bazel version", version)

def _find_goroot(ctx):
    if ctx.which("go"):  # go is available through path
        result = ctx.execute(["go", "env", "GOROOT"])
        if result.return_code != 0:
            fail("Failed to execute `go env GOROOT`, error:", result.stderr)
        return ctx.path(result.stdout.strip())

    # If go is not installed in the default way, require GOROOT to be set.
    if "GOROOT" in ctx.os.environ:
        return ctx.path(ctx.os.environ["GOROOT"].strip())

    # To be compatible with Liulishuo's linux docker, as the docker installs
    # Golang in /usr/lib/go
    result = ctx.execute(["test", "-f", "/usr/lib/go/bin/go"])
    if result.return_code == 0:  # file exist
        return ctx.path("/usr/lib/go")

    fail("Golang is not installed at default location, you must set $GOROOT to point to the local golang installation directory.")

def _go_local_sdk_impl(ctx):
    _check_bazel_version()

    goroot = _find_goroot(ctx)
    go_bin = goroot.get_child("bin").get_child("go")
    result = ctx.execute([go_bin, "version"])
    if result.return_code != 0:
        fail("Failed to execute `go version`, error:", result.stderr)
    go_version = result.stdout.strip()
    print("Using golang installed at %s, version [%s]" % (goroot, go_version))

    gobin = goroot.get_child("bin")
    gopkg = goroot.get_child("pkg")
    gosrc = goroot.get_child("src")
    ctx.symlink(gobin, "bin")
    ctx.symlink(gopkg, "pkg")
    ctx.symlink(gosrc, "src")
    ctx.file("BUILD.bazel", _GO_TOOLCHAIN_BUILD_FILE.format(
        goroot = goroot,
    ))

_go_local_sdk = repository_rule(
    _go_local_sdk_impl,
    environ = ["GOROOT"],
)

def go_repositories():
    _go_local_sdk(name = "io_bazel_rules_go_toolchain")
    _go_repository_tools(name = "io_bazel_rules_go_repository_tools")
