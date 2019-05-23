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

load("//go/private:dicts.bzl", "dicts")

_GAZELLE_ATTRS = {
    # Attributes for a repository that needs automatic build file generation
    "importpath": attr.string(mandatory = True),
    "build_tags": attr.string_list(),
    "build_file_generation": attr.string(
        default = "auto",
        values = ["on", "auto", "off"],
    ),
    "_gazelle": attr.label(
        default = Label("@io_bazel_rules_go_repository_tools//:bin/gazelle"),
        allow_files = True,
        single_file = True,
        executable = True,
        cfg = "host",
    ),
}

def _generate_build_files(ctx):
    """Function to generate build files for a downloaded repository. This allows
    one to write custom repository rules.

    Requires gazelle_utils.REPOSITORY_ATTRS are added to the repository rule.
    """
    if ctx.attr.build_file_generation == "off":
        return
    if ctx.attr.build_file_generation == "auto":
        # If a repository already has a WORKSPACE file, it already is a Bazel
        # repository. We will not generate BUILD file for it.
        path = ctx.path("WORKSPACE")
        if path.exists:
            print("Will not generate build files for Bazel repository", ctx.attr.importpath)
            return
    result = ctx.execute([
        ctx.path(ctx.attr._gazelle),
        "--go_prefix",
        ctx.attr.importpath,
        "--mode",
        "fix",
        "--repo_root",
        ctx.path(""),
        "--build_tags",
        ",".join(ctx.attr.build_tags),
        "--build_file_name",
        "BUILD.bazel",
        ctx.path(""),
    ])
    if result.return_code != 0:
        fail("failed to generate BUILD files for %s: %s" % (ctx.attr.importpath, result.stderr))

# Gazelle utils allows one to generate build files for repositories acquired in
# any way, be it http archive, git repository, local repository, etc.
gazelle_utils = struct(
    REPOSITORY_ATTRS = _GAZELLE_ATTRS,
    generate_build_files = _generate_build_files,
)

def _go_repository_impl(ctx):
    # If URL is specified, using URL first.
    urls = ctx.attr.urls
    if ctx.attr.url:
        urls = urls + [ctx.attr.url]
    if urls:  # download via URL.
        ctx.download_and_extract(
            url = urls,
            sha256 = ctx.attr.sha256,
            stripPrefix = ctx.attr.strip_prefix,
            type = ctx.attr.type,
        )
        gazelle_utils.generate_build_files(ctx)
        return

    # Download via version control systems.
    #
    # TODO(yi.sun): Switch to the optimized bazel git_repository.
    if ctx.attr.commit and ctx.attr.tag:
        fail("cannot specify both of commit and tag", "commit")
    if ctx.attr.commit:
        rev = ctx.attr.commit
    elif ctx.attr.tag:
        rev = ctx.attr.tag
    else:
        fail("neither commit or tag is specified", "commit")

    # Using fetch repo
    if ctx.attr.vcs and not ctx.attr.remote:
        fail("if vcs is specified, remote must also be")

    # TODO(yugui): support submodule?
    # c.f. https://www.bazel.io/versions/master/docs/be/workspace.html#git_repository.init_submodules
    result = ctx.execute([
        ctx.path(ctx.attr._fetch_repo),
        "--dest",
        ctx.path(""),
        "--remote",
        ctx.attr.remote,
        "--rev",
        rev,
        "--vcs",
        ctx.attr.vcs,
        "--importpath",
        ctx.attr.importpath,
    ])
    if result.return_code:
        fail("failed to fetch %s: %s" % (ctx.name, result.stderr))
    gazelle_utils.generate_build_files(ctx)

_HTTP_ATTRS = {
    "url": attr.string(),
    "urls": attr.string_list(),
    "strip_prefix": attr.string(),
    "type": attr.string(),
    "sha256": attr.string(),
}

_VCS_ATTRS = {
    "commit": attr.string(),
    "tag": attr.string(),
    # Attributes for a repository that cannot be inferred from the import path
    "vcs": attr.string(default = "", values = ["", "git", "hg", "svn", "bzr"]),
    "remote": attr.string(),
    # Hidden attributes for tool dependancies.
    "_fetch_repo": attr.label(
        default = Label("@io_bazel_rules_go_repository_tools//:bin/fetch_repo"),
        allow_files = True,
        single_file = True,
        executable = True,
        cfg = "host",
    ),
}

# NOTE(yi.sun): The go repository implementation is really a mix of http archive
# and git repository, with gazelle called afterwards. Therefore, it makes sense
# at this day to use the bazel http_archive and git_repository, which is
# optimized and performs much better than 2 years ago.
go_repository = repository_rule(
    implementation = _go_repository_impl,
    attrs = dicts.add(_HTTP_ATTRS, _VCS_ATTRS, gazelle_utils.REPOSITORY_ATTRS),
)
