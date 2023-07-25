load("//src/starkware/cairo/lang:cairo_rules.bzl", "cairo_binary", "cairo_library")
load("//bazel_utils:python.bzl", "py_exe", "pytest_test")
load("//bazel_utils:get_from_cairo_lang.bzl", "get_from_cairo_lang")

exports_files([
    "execute_batch.cairo",
    "execute_batch_utils.cairo",
    "main.cairo",
])

py_exe(
    name = "generate_perpetual_cairo_program_hash",
    args = ["--fix"],
    module = "services.perpetual.cairo.program_hash_test",
    deps = [
        "perpetual_cairo_program_hash_test_files",
        "perpetual_cairo_program_lib",
        "//src/starkware/cairo/bootloaders:program_hash_test_utils_lib",
        get_from_cairo_lang("//src/starkware/cairo/bootloaders:cairo_hash_program_lib"),
    ],
)

cairo_library(
    name = "perpetual_cairo_lib",
    srcs = [
        "//src/services/exchange/cairo:order.cairo",
        "//src/services/exchange/cairo:signature_message_hashes.cairo",
        "//src/services/exchange/cairo/definitions:constants.cairo",
        "//src/services/perpetual/cairo:execute_batch.cairo",
        "//src/services/perpetual/cairo:execute_batch_utils.cairo",
        "//src/services/perpetual/cairo:main.cairo",
        "//src/services/perpetual/cairo/definitions:constants.cairo",
        "//src/services/perpetual/cairo/definitions:general_config.cairo",
        "//src/services/perpetual/cairo/definitions:general_config_hash.cairo",
        "//src/services/perpetual/cairo/definitions:objects.cairo",
        "//src/services/perpetual/cairo/definitions:perpetual_error_code.cairo",
        "//src/services/perpetual/cairo/oracle:oracle_price.cairo",
        "//src/services/perpetual/cairo/order:limit_order.cairo",
        "//src/services/perpetual/cairo/order:order.cairo",
        "//src/services/perpetual/cairo/order:validate_limit_order.cairo",
        "//src/services/perpetual/cairo/output:data_availability.cairo",
        "//src/services/perpetual/cairo/output:forced.cairo",
        "//src/services/perpetual/cairo/output:program_input.cairo",
        "//src/services/perpetual/cairo/output:program_output.cairo",
        "//src/services/perpetual/cairo/position:add_asset.cairo",
        "//src/services/perpetual/cairo/position:check_smaller_holdings.cairo",
        "//src/services/perpetual/cairo/position:funding.cairo",
        "//src/services/perpetual/cairo/position:hash.cairo",
        "//src/services/perpetual/cairo/position:position.cairo",
        "//src/services/perpetual/cairo/position:serialize_change.cairo",
        "//src/services/perpetual/cairo/position:status.cairo",
        "//src/services/perpetual/cairo/position:update_position.cairo",
        "//src/services/perpetual/cairo/position:validate_state_transition.cairo",
        "//src/services/perpetual/cairo/state:state.cairo",
        "//src/services/perpetual/cairo/transactions:batch_config.cairo",
        "//src/services/perpetual/cairo/transactions:conditional_transfer.cairo",
        "//src/services/perpetual/cairo/transactions:deleverage.cairo",
        "//src/services/perpetual/cairo/transactions:deposit.cairo",
        "//src/services/perpetual/cairo/transactions:execute_limit_order.cairo",
        "//src/services/perpetual/cairo/transactions:forced_trade.cairo",
        "//src/services/perpetual/cairo/transactions:forced_withdrawal.cairo",
        "//src/services/perpetual/cairo/transactions:funding_tick.cairo",
        "//src/services/perpetual/cairo/transactions:liquidate.cairo",
        "//src/services/perpetual/cairo/transactions:oracle_prices_tick.cairo",
        "//src/services/perpetual/cairo/transactions:trade.cairo",
        "//src/services/perpetual/cairo/transactions:transaction.cairo",
        "//src/services/perpetual/cairo/transactions:transfer.cairo",
        "//src/services/perpetual/cairo/transactions:withdrawal.cairo",
    ],
)

cairo_binary(
    name = "perpetual_cairo_program",
    cairoopts = [
        "--debug_info_with_source",
    ],
    compiled_program_name = "perpetual_cairo_compiled.json",
    main = "main.cairo",
    deps = [":perpetual_cairo_lib"],
)

py_library(
    name = "perpetual_cairo_program_lib",
    srcs = [
    ],
    data = [
        ":perpetual_cairo_compiled.json",
    ],
    visibility = ["//visibility:public"],
    deps = [
        get_from_cairo_lang("//src/starkware/cairo/common:cairo_common_lib"),
    ],
)

pytest_test(
    name = "perpetual_cairo_program_hash_test",
    srcs = [
        "program_hash_test.py",
    ],
    data = [
        "program_hash.json",
        ":perpetual_cairo_compiled.json",
    ],
    visibility = ["//visibility:public"],
    deps = [
        "//src/starkware/cairo/bootloaders:program_hash_test_utils_lib",
        "//src/starkware/python:starkware_python_utils_lib",
    ],
)

package(default_visibility = ["//visibility:public"])

py_library(
    name = "perpetual_cairo_program_hash_test_files",
    srcs = [
        "program_hash_test.py",
    ],
    data = [
        "program_hash.json",
    ],
    visibility = ["//visibility:public"],
    deps = [
        "//src/starkware/cairo/bootloaders:program_hash_test_utils_lib",
        "//src/starkware/python:starkware_python_utils_lib",
    ],
)
