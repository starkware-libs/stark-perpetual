if (NOT DEFINED PERPETUAL_CAIRO_PROGRAM_LIB_ADDITIONAL_LIBS)
    set(PERPETUAL_CAIRO_PROGRAM_LIB_ADDITIONAL_LIBS pip_cairo_lang)
endif()
if (NOT DEFINED PERPETUAL_CAIRO_PROGRAM_HASH_TEST_LIB_ADDITIONAL_LIBS)
    set(PERPETUAL_CAIRO_PROGRAM_HASH_TEST_LIB_ADDITIONAL_LIBS pip_cairo_lang)
endif()

cairo_compile(perpetual_cairo_program
    perpetual_cairo_compiled.json main.cairo "--debug_info_with_source"
)

python_lib(perpetual_cairo_program_lib
    PREFIX services/perpetual/cairo

    LIBS
    ${PERPETUAL_CAIRO_PROGRAM_LIB_ADDITIONAL_LIBS}

    ARTIFACTS
    "${CMAKE_CURRENT_BINARY_DIR}/perpetual_cairo_compiled.json perpetual_cairo_compiled.json"

)

add_dependencies(perpetual_cairo_program_lib perpetual_cairo_program)

full_python_test(perpetual_cairo_program_hash_test
    PREFIX services/perpetual/cairo
    PYTHON ${PYTHON_COMMAND}
    TESTED_MODULES services/perpetual/cairo

    FILES
    program_hash.json
    program_hash_test.py

    LIBS
    perpetual_cairo_program_lib
    program_hash_test_utils_lib
    pip_pytest
    ${PERPETUAL_CAIRO_PROGRAM_HASH_TEST_LIB_ADDITIONAL_LIBS}
)

python_lib(perpetual_cairo_program_hash_test_files
    PREFIX services/perpetual/cairo

    FILES
    program_hash.json
    program_hash_test.py
)


python_venv(generate_perpetual_cairo_program_hash_venv
    PYTHON ${PYTHON_COMMAND}
    LIBS
    perpetual_cairo_program_hash_test_files
    perpetual_cairo_program_lib
    program_hash_test_utils_lib
    pip_pytest
    ${PERPETUAL_CAIRO_PROGRAM_HASH_TEST_LIB_ADDITIONAL_LIBS}
)


python_exe(generate_perpetual_cairo_program_hash
    VENV generate_perpetual_cairo_program_hash_venv
    MODULE services.perpetual.cairo.program_hash_test
    ARGS "--fix"
)
