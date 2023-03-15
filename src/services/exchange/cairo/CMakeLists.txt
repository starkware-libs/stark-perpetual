if (NOT DEFINED EXCHANGE_CAIRO_LIB_ADDITIONAL_LIBS)
    set(EXCHANGE_CAIRO_LIB_ADDITIONAL_LIBS pip_cairo_lang)
endif()

add_subdirectory(definitions)

python_lib(exchange_cairo_lib
    PREFIX services/exchange/cairo

    FILES
    order.cairo
    signature_message_hashes.cairo

    LIBS
    exchange_cairo_definitions_lib
    ${EXCHANGE_CAIRO_LIB_ADDITIONAL_LIBS}
)
