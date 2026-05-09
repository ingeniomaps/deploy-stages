#!/usr/bin/env bash
# Helpers de assertion mínimos para tests bash.
# Uso: source tests/lib/assert.sh

# Contadores globales — reset en run.sh entre archivos.
TESTS_RUN=${TESTS_RUN:-0}
TESTS_PASSED=${TESTS_PASSED:-0}
TESTS_FAILED=${TESTS_FAILED:-0}
FAILED_NAMES=${FAILED_NAMES:-}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "${expected}" == "${actual}" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf '  \033[0;32m✓\033[0m %s\n' "${msg:-assert_equals}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_NAMES="${FAILED_NAMES}\n    ${msg}"
        printf '  \033[0;31m✗\033[0m %s\n      expected: %s\n      actual:   %s\n' "${msg:-assert_equals}" "${expected}" "${actual}"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "${haystack}" == *"${needle}"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf '  \033[0;32m✓\033[0m %s\n' "${msg:-assert_contains}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_NAMES="${FAILED_NAMES}\n    ${msg}"
        printf '  \033[0;31m✗\033[0m %s\n      needle: %s\n      not in: %s\n' "${msg:-assert_contains}" "${needle}" "${haystack}"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "${haystack}" != *"${needle}"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf '  \033[0;32m✓\033[0m %s\n' "${msg:-assert_not_contains}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_NAMES="${FAILED_NAMES}\n    ${msg}"
        printf '  \033[0;31m✗\033[0m %s\n      needle: %s\n      WAS in: %s\n' "${msg:-assert_not_contains}" "${needle}" "${haystack}"
    fi
}

assert_exit_zero() {
    local cmd_label="$1"
    local actual_exit="$2"
    local msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "${actual_exit}" -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf '  \033[0;32m✓\033[0m %s\n' "${msg:-${cmd_label} exit 0}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_NAMES="${FAILED_NAMES}\n    ${msg}"
        printf '  \033[0;31m✗\033[0m %s\n      cmd:  %s\n      exit: %d (esperado 0)\n' "${msg:-assert_exit_zero}" "${cmd_label}" "${actual_exit}"
    fi
}

assert_exit_nonzero() {
    local cmd_label="$1"
    local actual_exit="$2"
    local msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "${actual_exit}" -ne 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf '  \033[0;32m✓\033[0m %s\n' "${msg:-${cmd_label} exit != 0}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_NAMES="${FAILED_NAMES}\n    ${msg}"
        printf '  \033[0;31m✗\033[0m %s\n      cmd:  %s\n      exit: 0 (esperado != 0)\n' "${msg:-assert_exit_nonzero}" "${cmd_label}"
    fi
}
