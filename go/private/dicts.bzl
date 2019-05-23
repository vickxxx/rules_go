def _add(*dicts):
    """Union the input dictionaries

    NOTE(yi.sun): This is to avoid pulling in @bazel_skylib//lib:dicts.bzl for
    one function.
    """
    output = {}
    for d in dicts:
        output.update(d)
    return output

dicts = struct(
    add = _add,
)
