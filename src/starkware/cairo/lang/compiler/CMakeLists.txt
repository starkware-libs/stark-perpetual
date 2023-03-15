python_venv(cairo_lang_compile_venv
    PYTHON ${PYTHON_COMMAND}

    LIBS
    pip_cairo_lang
)

python_exe(cairo_compile_exe
    VENV cairo_lang_compile_venv
    MODULE starkware.cairo.lang.compiler.cairo_compile
)
