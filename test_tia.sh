#!/bin/zsh

# Test suite for tia.sh
# Tests argument parsing, profile resolution, and output generation
# Does NOT execute any real terraform commands

# Note: Not using set -e because we intentionally test error conditions

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TIA="$SCRIPT_DIR/tia.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
pass() {
  ((TESTS_PASSED++))
  echo -e "${GREEN}✓${NC} $1"
}

fail() {
  ((TESTS_FAILED++))
  echo -e "${RED}✗${NC} $1"
  if [[ -n "$2" ]]; then
    echo -e "  ${YELLOW}Expected:${NC} $2"
  fi
  if [[ -n "$3" ]]; then
    echo -e "  ${YELLOW}Got:${NC} $3"
  fi
}

run_test() {
  ((TESTS_RUN++))
}

# ==============================
# Test: --version flag
# ==============================
test_version() {
  run_test
  local output
  output=$("$TIA" --version 2>&1)
  if [[ "$output" == tia\ * ]]; then
    pass "--version outputs version string"
  else
    fail "--version outputs version string" "tia X.Y.Z" "$output"
  fi
}

# ==============================
# Test: -V flag (short version)
# ==============================
test_version_short() {
  run_test
  local output
  output=$("$TIA" -V 2>&1)
  if [[ "$output" == tia\ * ]]; then
    pass "-V outputs version string"
  else
    fail "-V outputs version string" "tia X.Y.Z" "$output"
  fi
}

# ==============================
# Test: --help flag
# ==============================
test_help() {
  run_test
  local output
  output=$("$TIA" --help 2>&1)
  if [[ "$output" == *"USAGE:"* && "$output" == *"COMMANDS:"* ]]; then
    pass "--help outputs usage information"
  else
    fail "--help outputs usage information" "Contains USAGE: and COMMANDS:" "$output"
  fi
}

# ==============================
# Test: -h flag (short help)
# ==============================
test_help_short() {
  run_test
  local output
  output=$("$TIA" -h 2>&1)
  if [[ "$output" == *"USAGE:"* && "$output" == *"COMMANDS:"* ]]; then
    pass "-h outputs usage information"
  else
    fail "-h outputs usage information" "Contains USAGE: and COMMANDS:" "$output"
  fi
}

# ==============================
# Test: Missing environment variables
# ==============================
test_missing_env_vars() {
  run_test
  local output
  local exit_code=0
  output=$(AWS_ENV="" AWS_PROFILE="" TF_KEY="" "$TIA" args 2>&1) || exit_code=$?
  if [[ $exit_code -ne 0 && "$output" == *"Missing required environment variables"* ]]; then
    pass "Missing env vars produces error"
  else
    fail "Missing env vars produces error" "Exit code != 0 and error message" "exit=$exit_code, output=$output"
  fi
}

# ==============================
# Test: Missing only AWS_ENV
# ==============================
test_missing_aws_env() {
  run_test
  local output
  local exit_code=0
  output=$(AWS_ENV="" AWS_PROFILE="augdev" TF_KEY="test" "$TIA" args 2>&1) || exit_code=$?
  if [[ $exit_code -ne 0 && "$output" == *"AWS_ENV"* ]]; then
    pass "Missing AWS_ENV listed in error"
  else
    fail "Missing AWS_ENV listed in error" "Error mentioning AWS_ENV" "exit=$exit_code"
  fi
}

# ==============================
# Test: Unknown command
# ==============================
test_unknown_command() {
  run_test
  local output
  local exit_code=0
  output=$(AWS_ENV="dev" AWS_PROFILE="augdev" TF_KEY="test" "$TIA" notarealcommand 2>&1) || exit_code=$?
  if [[ $exit_code -ne 0 && "$output" == *"Unknown command"* ]]; then
    pass "Unknown command produces error"
  else
    fail "Unknown command produces error" "Exit code != 0 and 'Unknown command'" "exit=$exit_code, output=$output"
  fi
}

# ==============================
# Test: Unknown flag
# ==============================
test_unknown_flag() {
  run_test
  local output
  local exit_code=0
  output=$(AWS_ENV="dev" AWS_PROFILE="augdev" TF_KEY="test" "$TIA" --notaflag 2>&1) || exit_code=$?
  if [[ $exit_code -ne 0 && "$output" == *"Unknown option"* ]]; then
    pass "Unknown flag produces error"
  else
    fail "Unknown flag produces error" "Exit code != 0 and 'Unknown option'" "exit=$exit_code, output=$output"
  fi
}

# ==============================
# Test: Unrecognized profile prefix
# ==============================
test_unrecognized_profile() {
  run_test
  local output
  local exit_code=0
  output=$(AWS_ENV="dev" AWS_PROFILE="unknownprefix-dev" TF_KEY="test" "$TIA" args 2>&1) || exit_code=$?
  if [[ $exit_code -ne 0 && "$output" == *"Unrecognized profile prefix"* ]]; then
    pass "Unrecognized profile prefix produces error"
  else
    fail "Unrecognized profile prefix produces error" "Error about profile prefix" "exit=$exit_code, output=$output"
  fi
}

# ==============================
# Test: tia args output for aug profile
# ==============================
test_args_aug_profile() {
  run_test
  local output
  output=$(AWS_ENV="dev" AWS_PROFILE="augdev" TF_KEY="my-module" "$TIA" args 2>&1)
  
  local all_ok=true
  
  # Check bucket name
  if [[ "$output" != *"augmetrics-tfstate-dev"* ]]; then
    all_ok=false
  fi
  
  # Check TF_KEY in path
  if [[ "$output" != *"key=my-module/terraform.tfstate"* ]]; then
    all_ok=false
  fi
  
  # Check dynamodb table
  if [[ "$output" != *"dynamodb_table=tfstate_dev"* ]]; then
    all_ok=false
  fi
  
  if [[ "$all_ok" == true ]]; then
    pass "tia args produces correct output for aug profile"
  else
    fail "tia args produces correct output for aug profile" "Contains augmetrics-tfstate-dev, my-module, tfstate_dev" "$output"
  fi
}

# ==============================
# Test: tia args output for vm profile
# ==============================
test_args_vm_profile() {
  run_test
  local output
  output=$(AWS_ENV="prod" AWS_PROFILE="vm-prod" TF_KEY="infra" "$TIA" args 2>&1)
  
  local all_ok=true
  
  # Check bucket name uses vm prefix
  if [[ "$output" != *"vm-tfstate-prod"* ]]; then
    all_ok=false
  fi
  
  # Check TF_KEY in path
  if [[ "$output" != *"key=infra/terraform.tfstate"* ]]; then
    all_ok=false
  fi
  
  # Check dynamodb table
  if [[ "$output" != *"dynamodb_table=tfstate_prod"* ]]; then
    all_ok=false
  fi
  
  if [[ "$all_ok" == true ]]; then
    pass "tia args produces correct output for vm profile"
  else
    fail "tia args produces correct output for vm profile" "Contains vm-tfstate-prod, infra, tfstate_prod" "$output"
  fi
}

# ==============================
# Test: tia args --eval format
# ==============================
test_args_eval_format() {
  run_test
  local output
  output=$(AWS_ENV="dev" AWS_PROFILE="augdev" TF_KEY="test-key" "$TIA" args --eval 2>&1)
  
  local all_ok=true
  
  # Check INIT_ARGS is set
  if [[ "$output" != *"INIT_ARGS="* ]]; then
    all_ok=false
  fi
  
  # Check VAR_ARGS is set
  if [[ "$output" != *"VAR_ARGS="* ]]; then
    all_ok=false
  fi
  
  # Check it contains backend-config
  if [[ "$output" != *"backend-config"* ]]; then
    all_ok=false
  fi
  
  if [[ "$all_ok" == true ]]; then
    pass "tia args --eval produces eval-able output"
  else
    fail "tia args --eval produces eval-able output" "Contains INIT_ARGS=, VAR_ARGS=, backend-config" "$output"
  fi
}

# ==============================
# Test: tia args --eval is actually eval-able
# ==============================
test_args_eval_executable() {
  run_test
  local output
  local exit_code=0
  
  # Get the eval output and try to eval it
  output=$(AWS_ENV="dev" AWS_PROFILE="augdev" TF_KEY="test-key" "$TIA" args --eval 2>&1)
  
  # Try to eval and check INIT_ARGS is set
  eval "$output" 2>/dev/null || exit_code=$?
  
  if [[ $exit_code -eq 0 && -n "$INIT_ARGS" ]]; then
    pass "tia args --eval output can be eval'd and sets INIT_ARGS"
  else
    fail "tia args --eval output can be eval'd and sets INIT_ARGS" "INIT_ARGS should be set after eval" "exit=$exit_code, INIT_ARGS=$INIT_ARGS"
  fi
  
  # Clean up
  unset INIT_ARGS VAR_ARGS
}

# ==============================
# Test: import requires address and id
# ==============================
test_import_requires_args() {
  run_test
  local output
  local exit_code=0
  output=$(AWS_ENV="dev" AWS_PROFILE="augdev" TF_KEY="test" "$TIA" import 2>&1) || exit_code=$?
  if [[ $exit_code -ne 0 && "$output" == *"import requires"* ]]; then
    pass "import without args produces error"
  else
    fail "import without args produces error" "Error about missing args" "exit=$exit_code, output=$output"
  fi
}

# ==============================
# Test: state requires subcommand
# ==============================
test_state_requires_subcommand() {
  run_test
  local output
  local exit_code=0
  output=$(AWS_ENV="dev" AWS_PROFILE="augdev" TF_KEY="test" "$TIA" state 2>&1) || exit_code=$?
  if [[ $exit_code -ne 0 && "$output" == *"Unknown state command"* ]]; then
    pass "state without subcommand produces error"
  else
    fail "state without subcommand produces error" "Error about state command" "exit=$exit_code, output=$output"
  fi
}

# ==============================
# Test: state show requires address
# ==============================
test_state_show_requires_address() {
  run_test
  local output
  local exit_code=0
  output=$(AWS_ENV="dev" AWS_PROFILE="augdev" TF_KEY="test" "$TIA" state show 2>&1) || exit_code=$?
  if [[ $exit_code -ne 0 && "$output" == *"state show requires"* ]]; then
    pass "state show without address produces error"
  else
    fail "state show without address produces error" "Error about missing address" "exit=$exit_code, output=$output"
  fi
}

# ==============================
# Test: state rm requires address
# ==============================
test_state_rm_requires_address() {
  run_test
  local output
  local exit_code=0
  output=$(AWS_ENV="dev" AWS_PROFILE="augdev" TF_KEY="test" "$TIA" state rm 2>&1) || exit_code=$?
  if [[ $exit_code -ne 0 && "$output" == *"state rm requires"* ]]; then
    pass "state rm without address produces error"
  else
    fail "state rm without address produces error" "Error about missing address" "exit=$exit_code, output=$output"
  fi
}

# ==============================
# Test: state mv requires both args
# ==============================
test_state_mv_requires_args() {
  run_test
  local output
  local exit_code=0
  output=$(AWS_ENV="dev" AWS_PROFILE="augdev" TF_KEY="test" "$TIA" state mv only_one_arg 2>&1) || exit_code=$?
  if [[ $exit_code -ne 0 && "$output" == *"state mv requires"* ]]; then
    pass "state mv with one arg produces error"
  else
    fail "state mv with one arg produces error" "Error about missing args" "exit=$exit_code, output=$output"
  fi
}

# ==============================
# Test: TF_KEY from file takes precedence
# ==============================
test_tf_key_file_precedence() {
  run_test
  
  # Create a temp directory to test in
  local tmpdir
  tmpdir=$(mktemp -d)
  
  # Create a TF_KEY file
  echo "key-from-file" > "$tmpdir/TF_KEY"
  
  # Run tia args from that directory with a different TF_KEY env var
  local output
  output=$(cd "$tmpdir" && AWS_ENV="dev" AWS_PROFILE="augdev" TF_KEY="key-from-env" "$TIA" args 2>&1)
  
  # Clean up
  rm -rf "$tmpdir"
  
  if [[ "$output" == *"key=key-from-file/terraform.tfstate"* ]]; then
    pass "TF_KEY file takes precedence over env var"
  else
    fail "TF_KEY file takes precedence over env var" "key=key-from-file/terraform.tfstate" "$output"
  fi
}

# ==============================
# Test: Different AWS_ENV values
# ==============================
test_different_environments() {
  run_test
  local output_dev output_prod
  
  output_dev=$(AWS_ENV="dev" AWS_PROFILE="augdev" TF_KEY="test" "$TIA" args 2>&1)
  output_prod=$(AWS_ENV="prod" AWS_PROFILE="augprod" TF_KEY="test" "$TIA" args 2>&1)
  
  local all_ok=true
  
  if [[ "$output_dev" != *"tfstate-dev"* ]]; then
    all_ok=false
  fi
  
  if [[ "$output_prod" != *"tfstate-prod"* ]]; then
    all_ok=false
  fi
  
  if [[ "$output_dev" != *"tfstate_dev"* ]]; then
    all_ok=false
  fi
  
  if [[ "$output_prod" != *"tfstate_prod"* ]]; then
    all_ok=false
  fi
  
  if [[ "$all_ok" == true ]]; then
    pass "Different AWS_ENV values produce different bucket/table names"
  else
    fail "Different AWS_ENV values produce different bucket/table names" "dev uses tfstate-dev, prod uses tfstate-prod" ""
  fi
}

# ==============================
# Run all tests
# ==============================
echo ""
echo "=================================="
echo "  tia.sh Test Suite"
echo "=================================="
echo ""

# Version and help tests
test_version
test_version_short
test_help
test_help_short

# Error handling tests
test_missing_env_vars
test_missing_aws_env
test_unknown_command
test_unknown_flag
test_unrecognized_profile

# Args output tests
test_args_aug_profile
test_args_vm_profile
test_args_eval_format
test_args_eval_executable

# Subcommand argument validation tests
test_import_requires_args
test_state_requires_subcommand
test_state_show_requires_address
test_state_rm_requires_address
test_state_mv_requires_args

# Configuration tests
test_tf_key_file_precedence
test_different_environments

# Summary
echo ""
echo "=================================="
echo "  Results"
echo "=================================="
echo ""
echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
if [[ $TESTS_FAILED -gt 0 ]]; then
  echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
  exit 1
else
  echo -e "Tests failed: $TESTS_FAILED"
  echo ""
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
fi

