load("//bazel_utils/python:defs.bzl", "requirement")
load("//bazel_utils:python.bzl", "pytest_test")
load("//src/services/perpetual/public:vars.bzl", "PERPETUAL_PUBLIC_LIB_ADDITIONAL_LIBS")

exports_files([
    "committee_config.yml",
    "committee_private_key.txt",
])

package(default_visibility = ["//visibility:public"])

py_library(
    name = "perpetual_public_lib",
    srcs = [
        "generate_perpetual_config_hash.py",
        "perpetual_messages.py",
        "stark_cli.py",
    ],
    visibility = ["//visibility:public"],
    deps = [
        "//src/starkware/python:starkware_python_utils_lib",
        requirement("mypy_extensions"),
        requirement("pyyaml"),
        requirement("web3"),
    ] + PERPETUAL_PUBLIC_LIB_ADDITIONAL_LIBS,
)

pytest_test(
    name = "starkware_perpetual_public_test",
    srcs = [
        "perpetual_messages_test.py",
        "stark_cli_test.py",
    ],
    data = [
        "perpetual_messages_precomputed.json",
        ":keys_precomputed.json",
        ":signature_test_data.json",
    ],
    visibility = ["//visibility:public"],
    deps = [
        "perpetual_public_lib",
    ],
)

genrule(
    name = "copy_artifacts_for_starkware_perpetual_public_test",
    srcs = [
        "//src/starkware/crypto/signature/test/config:signature_test_data.json",
        "//src/starkware/crypto/signature/src/config:keys_precomputed.json",
    ],
    outs = [
        "signature_test_data.json",
        "keys_precomputed.json",
    ],
    cmd = "\
        cp $(execpath //src/starkware/crypto/signature/test/config:signature_test_data.json) $(execpath signature_test_data.json) && \
        cp $(execpath //src/starkware/crypto/signature/src/config:keys_precomputed.json) $(execpath keys_precomputed.json)",
)
