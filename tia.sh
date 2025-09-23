#!/bin/zsh

# Version
TIA_VERSION="0.2.0"

# ==============================
# Config: project/company mappings
# Edit these in one place to add or change prefixes
# ==============================
typeset -A PROFILE_BUCKET_PREFIX_MAP
PROFILE_BUCKET_PREFIX_MAP=(
  aug "augmetrics"
  bsa "bsa"
  vm  "vm"
)

typeset -A PROFILE_ALLOWED_DIR_PREFIXES_MAP
PROFILE_ALLOWED_DIR_PREFIXES_MAP=(
  aug "aug adw"
  bsa "bsa"
  vm  "vm"
)

# Default values for optional flags
apply_only=false

# Utility: echo the command exactly as it will be executed, then run it
run_and_echo() {
  local cmd="$1"; shift
  local -a parts
  parts=("$cmd" "$@")
  print -r -- "+ ${(q)parts[@]}"
  "$cmd" "$@"
}

# Parse optional flags
# Handle --version early (non-blocking, before getopts)
for arg in "$@"; do
  if [[ "$arg" == "--version" || "$arg" == "-V" ]]; then
    echo "tia $TIA_VERSION"
    exit 0
  fi
done

while getopts "a" opt; do
  case $opt in
    a) apply_only=true ;;
    *) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

# Resolve TF_KEY: first check for local file, then fall back to environment variable
tf_key_resolved=""
if [[ -f "./TF_KEY" ]]; then
    # Read the first line of the TF_KEY file, stripping any trailing whitespace/newlines
    tf_key_resolved=$(head -n 1 ./TF_KEY | tr -d '\n\r')
    if [[ -z "$tf_key_resolved" ]]; then
        echo "❌ Error: TF_KEY file exists but is empty"
        exit 1
    fi
    echo "🔑 Using TF_KEY from local file: ./TF_KEY"
    TF_KEY="$tf_key_resolved"
elif [[ -n "$TF_KEY" ]]; then
    echo "🔑 Using TF_KEY from environment variable"
else
    tf_key_resolved=""
fi

# Check for required environment variables
missing_vars=()
[[ -z "$AWS_ENV" ]] && missing_vars+=("AWS_ENV")
[[ -z "$AWS_PROFILE" ]] && missing_vars+=("AWS_PROFILE")
[[ -z "$tf_key_resolved" && -z "$TF_KEY" ]] && missing_vars+=("TF_KEY")

if [[ ${#missing_vars[@]} -gt 0 ]]; then
  echo -e "\n❌ Missing required environment variables:"
  for var in "${missing_vars[@]}"; do
    echo "  - $var"
  done
  echo -e "\nPlease export the missing variables and try again."
  exit 1
fi

# Resolve short account prefix from AWS_PROFILE using configured keys
PROFILE_PREFIX=${AWS_PROFILE%%-*}
lower_profile_prefix=${(L)PROFILE_PREFIX}
ACCOUNT_PREFIX_SHORT=""
for key in ${(k)PROFILE_BUCKET_PREFIX_MAP}; do
  if [[ ${lower_profile_prefix} == ${key}* ]]; then
    ACCOUNT_PREFIX_SHORT="$key"
    break
  fi
done

if [[ -z "$ACCOUNT_PREFIX_SHORT" ]]; then
  echo "Error: Unrecognized profile prefix '${PROFILE_PREFIX}'. Please use a supported profile."
  exit 1
fi

# Early safety check: warn and prompt if AWS profile prefix doesn't match allowed ~/devel/<prefix>/ directory
if [[ "$PWD" == "$HOME/devel/"* ]]; then
    dir_after_devel="${PWD#"$HOME/devel/"}"
    dir_account_prefix="${dir_after_devel%%/*}"
    lower_dir_prefix=${(L)dir_account_prefix}
    # Define allowed directory prefixes for a given AWS profile prefix (case-insensitive)
    typeset -a allowed_dir_prefixes
    allowed_string="${PROFILE_ALLOWED_DIR_PREFIXES_MAP[$ACCOUNT_PREFIX_SHORT]}"
    [[ -n "$allowed_string" ]] && allowed_dir_prefixes=(${=allowed_string}) || allowed_dir_prefixes=()

    # Only check when we have a directory prefix and known allowed prefixes
    if [[ -n "$lower_dir_prefix" && ${#allowed_dir_prefixes[@]} -gt 0 ]]; then
        local match_ok=false
        for pfx in "${allowed_dir_prefixes[@]}"; do
            if [[ "$lower_dir_prefix" == "$pfx" ]]; then
                match_ok=true
                break
            fi
        done

        if [[ "$match_ok" != true ]]; then
            printf "\n\033[1;31m⚠️⚠️⚠️  WARNING:\033[0m AWS_PROFILE '%s' does not appear to match directory prefix '%s' (%s)\n" \
                "$AWS_PROFILE" "$dir_account_prefix" "$PWD"
            echo "Allowed directory prefixes for this profile: ${allowed_dir_prefixes[*]}"
            echo "Consider switching profiles (export AWS_PROFILE=...) or double-checking before applying."
            echo -n "Are you sure you want to continue? (y/N): "
            read mismatch_confirm
            if [[ ! $mismatch_confirm == [yY] ]]; then
                echo "❌ Operation canceled."
                exit 1
            fi
            echo
        fi
    fi
fi

# Determine the bucket prefix based on the profile (from config map)
TF_BUCKET_PREFIX="${PROFILE_BUCKET_PREFIX_MAP[$ACCOUNT_PREFIX_SHORT]}"
if [[ -z "$TF_BUCKET_PREFIX" ]]; then
  echo "Error: No bucket prefix configured for profile key '$ACCOUNT_PREFIX_SHORT' (from '$AWS_PROFILE')."
  exit 1
fi

# Construct the full bucket name
TF_BUCKET="s3://${TF_BUCKET_PREFIX}-tfstate-${AWS_ENV}"

# Check for tfvars file location
var_file="env-${AWS_ENV}.tfvars"
var_file_path=""

if [[ -f "./${var_file}" ]]; then
    var_file_path="./${var_file}"
elif [[ -f "../${var_file}" ]]; then
    var_file_path="../${var_file}"
    echo -e "\n⚠️  Note: Using tfvars file from parent directory: ../${var_file}"
    echo -n "Continue with parent directory tfvars file? (y/N): "
    read parent_confirm
    if [[ ! $parent_confirm == [yY] ]]; then
        echo "❌ Operation canceled."
        exit 1
    fi
else
    echo -e "\n❌ Error: Could not find ${var_file} in current or parent directory"
    exit 1
fi

# Review the settings
echo -e "\n🔍 Review the following settings:"
echo "AWS_ENV: $AWS_ENV"
echo "AWS_PROFILE: $AWS_PROFILE"
echo "TF_KEY: $TF_KEY"
echo "TF_BUCKET: $TF_BUCKET"
echo "TFVARS File: $var_file_path"
echo -e "-----------------------------------\n"
echo -n "Proceed with these settings? (y/N): "
read confirm

# Default to "No" if the input is empty
if [[ $confirm == [yY] ]]; then
    # Delete .terraform directory unless running with -a (apply-only mode)
    if [[ $apply_only == false ]]; then
        echo "Removing .terraform directory..."
        rm -rf .terraform

        # Terraform init with backend configuration
        echo "Initializing Terraform..."
        INIT_ARGS=(
            -backend-config="bucket=${TF_BUCKET_PREFIX}-tfstate-${AWS_ENV}"
            -backend-config="key=${TF_KEY}/terraform.tfstate"
            -backend-config="region=us-east-1"
            -backend-config="dynamodb_table=tfstate_${AWS_ENV}"
        )
        run_and_echo terraform init "${INIT_ARGS[@]}"
    else
        echo "Skipping Terraform init due to apply-only mode (-a)."
    fi

    # Apply Terraform configuration
    echo "Applying Terraform configuration..."
    APPLY_ARGS=(
        -var-file "${var_file_path}"
    )
    run_and_echo terraform apply "${APPLY_ARGS[@]}"

    echo "✅ Terraform init and apply complete."
else
    echo "❌ Operation canceled."
fi
