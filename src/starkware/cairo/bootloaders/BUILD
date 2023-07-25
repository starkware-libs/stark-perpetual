load("//bazel_utils:get_from_cairo_lang.bzl", "get_from_cairo_lang")

py_library(
    name = "program_hash_test_utils_lib",
    srcs = [
        "program_hash_test_utils.py",
    ],
    visibility = ["//visibility:public"],
    deps = [
        get_from_cairo_lang("//src/starkware/cairo/bootloaders:cairo_hash_program_lib"),
    ],
)

package(default_visibility = ["//visibility:public"])
