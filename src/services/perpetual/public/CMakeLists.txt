python_lib(perpetual_public_lib
    PREFIX services/perpetual/public

    FILES
    perpetual_messages.py
    public_generate_perpetual_config_hash.py
    stark_cli.py

    LIBS
    starkware_crypto_lib
    pip_mypy_extensions
    pip_pyyaml
    pip_web3
)


python_venv(perpetual_public_venv
    PYTHON python3.7
    LIBS
    perpetual_public_lib
)


full_python_test(perpetual_public_test
    PREFIX services/perpetual/public
    PYTHON python3.7

    FILES
    perpetual_messages_test.py
    perpetual_messages_precomputed.json
    stark_cli_test.py

    LIBS
    perpetual_public_lib
    pip_pytest

    ARTIFACTS
    "${CMAKE_SOURCE_DIR}/src/starkware/crypto/starkware/crypto/signature/signature_test_data.json signature_test_data.json"
    "${CMAKE_SOURCE_DIR}/src/starkware/crypto/starkware/crypto/signature/keys_precomputed.json keys_precomputed.json"
)
