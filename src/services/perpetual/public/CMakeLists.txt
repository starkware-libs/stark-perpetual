python_lib(perpetual_public_lib
    PREFIX services/perpetual/public

    FILES
    perpetual_messages.py
    generate_perpetual_config_hash.py
    stark_cli.py

    LIBS
    starkware_crypto_lib
    starkware_python_utils_lib
    pip_mypy_extensions
    pip_pyyaml
    pip_web3
)


python_venv(perpetual_public_venv
    PYTHON ${PYTHON_COMMAND}
    LIBS
    perpetual_public_lib
)


full_python_test(perpetual_public_test
    PREFIX services/perpetual/public
    PYTHON ${PYTHON_COMMAND}

    FILES
    perpetual_messages_test.py
    perpetual_messages_precomputed.json
    stark_cli_test.py

    LIBS
    perpetual_public_lib
    pip_pytest

    ARTIFACTS
    "${CMAKE_SOURCE_DIR}/src/starkware/crypto/signature/test/config/signature_test_data.json signature_test_data.json"
    "${CMAKE_SOURCE_DIR}/src/starkware/crypto/signature/src/config/keys_precomputed.json keys_precomputed.json"
)
