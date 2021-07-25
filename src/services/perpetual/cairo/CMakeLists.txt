cairo_compile(perpetual_cairo_program
    perpetual_cairo_compiled.json main.cairo "--debug_info_with_source"
)

python_lib(perpetual_cairo_program_lib
    PREFIX services/perpetual/cairo

    ARTIFACTS
    "${CMAKE_CURRENT_BINARY_DIR}/perpetual_cairo_compiled.json perpetual_cairo_compiled.json"

    LIBS
    cairo_common_lib
)

add_dependencies(perpetual_cairo_program_lib perpetual_cairo_program)

python_lib(perpetual_cairo_program_hash_test_lib
    PREFIX services/perpetual/cairo
    FILES
    program_hash_test.py
    LIBS
    cairo_hash_program_lib
    perpetual_cairo_program_lib
    pip_pytest
)

python_venv(perpetual_cairo_program_hash_test_venv
    PYTHON python3.7
    LIBS
    perpetual_cairo_program_hash_test_lib
)

python_test(perpetual_cairo_program_hash_test
    VENV perpetual_cairo_program_hash_test_venv
    TESTED_MODULES services/perpetual/cairo
)

python_exe(generate_perpetual_cairo_program_hash
    VENV perpetual_cairo_program_hash_test_venv
    MODULE services.perpetual.cairo.program_hash_test
    ARGS "--fix"
)
