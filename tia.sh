#!/bin/zsh

# Version
TIA_VERSION="0.3.0"

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
skip_init=false

# Utility: echo the command exactly as it will be executed, then run it
run_and_echo() {
  local cmd="$1"; shift
  local -a parts
  parts=("$cmd" "$@")
  print -r -- "+ ${(q)parts[@]}"
  "$cmd" "$@"
}

# Show help
show_help() {
  cat << 'EOF'
tia - Terraform Init Apply (and more)

USAGE:
  tia [OPTIONS] [COMMAND] [ARGS...]

COMMANDS:
  apply              Initialize and apply (default if no command given)
  destroy            Initialize and destroy
  plan               Initialize and plan
  init               Initialize only (no apply)
  import <addr> <id> Import existing resource into state
  state list         List resources in state
  state show <addr>  Show a resource in state
  state rm <addr>    Remove a resource from state
  state mv <src> <dst> Move/rename a resource in state
  args [--eval]      Output computed arguments for manual use

OPTIONS:
  -a, --no-init      Skip terraform init (use existing .terraform)
  -V, --version      Show version
  -h, --help         Show this help

EXAMPLES:
  tia                           # init + apply (default)
  tia plan                      # init + plan
  tia destroy                   # init + destroy
  tia -a apply                  # apply only (skip init)
  tia --no-init destroy         # destroy only (skip init)
  tia import aws_s3_bucket.foo my-bucket
  tia state list
  tia state rm aws_s3_bucket.foo
  tia args                      # show args for copy/paste
  tia args --eval               # show args for eval $(tia args --eval)

ENVIRONMENT:
  AWS_ENV       Required. Environment name (dev, prod, etc.)
  AWS_PROFILE   Required. AWS CLI profile to use
  TF_KEY        Required. Terraform state key (or use ./TF_KEY file)
EOF
}

# Handle --version and --help early (before other parsing)
for arg in "$@"; do
  case "$arg" in
    --version|-V)
      echo "tia $TIA_VERSION"
      exit 0
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
  esac
done

# Parse flags (must come before subcommand)
while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--no-init)
      skip_init=true
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Use 'tia --help' for usage information." >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

# Get subcommand (default to "apply")
SUBCOMMAND="${1:-apply}"
shift 2>/dev/null || true

# ==============================
# Environment resolution
# ==============================

# Resolve TF_KEY: first check for local file, then fall back to environment variable
tf_key_resolved=""
if [[ -f "./TF_KEY" ]]; then
    tf_key_resolved=$(head -n 1 ./TF_KEY | tr -d '\n\r')
    if [[ -z "$tf_key_resolved" ]]; then
        echo "❌ Error: TF_KEY file exists but is empty"
        exit 1
    fi
    TF_KEY="$tf_key_resolved"
elif [[ -n "$TF_KEY" ]]; then
    tf_key_resolved="$TF_KEY"
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
perform_safety_check() {
  if [[ "$PWD" == "$HOME/devel/"* ]]; then
      dir_after_devel="${PWD#"$HOME/devel/"}"
      dir_account_prefix="${dir_after_devel%%/*}"
      lower_dir_prefix=${(L)dir_account_prefix}
      typeset -a allowed_dir_prefixes
      allowed_string="${PROFILE_ALLOWED_DIR_PREFIXES_MAP[$ACCOUNT_PREFIX_SHORT]}"
      [[ -n "$allowed_string" ]] && allowed_dir_prefixes=(${=allowed_string}) || allowed_dir_prefixes=()

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
}

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
fi

# Build init args array
build_init_args() {
  INIT_ARGS=(
    -backend-config="bucket=${TF_BUCKET_PREFIX}-tfstate-${AWS_ENV}"
    -backend-config="key=${TF_KEY}/terraform.tfstate"
    -backend-config="region=us-east-1"
    -backend-config="dynamodb_table=tfstate_${AWS_ENV}"
  )
}

# Build var-file args
build_var_args() {
  if [[ -n "$var_file_path" ]]; then
    VAR_ARGS=(-var-file "$var_file_path")
  else
    VAR_ARGS=()
  fi
}

# Run terraform init
do_init() {
  echo "Removing .terraform directory..."
  rm -rf .terraform
  echo "Initializing Terraform..."
  build_init_args
  run_and_echo terraform init "${INIT_ARGS[@]}"
}

# ==============================
# Subcommand handlers
# ==============================

cmd_args() {
  local eval_mode=false
  [[ "$1" == "--eval" ]] && eval_mode=true

  build_init_args
  build_var_args

  if [[ "$eval_mode" == true ]]; then
    # Output for eval $(tia args --eval)
    echo "INIT_ARGS='${INIT_ARGS[*]}'"
    if [[ -n "$var_file_path" ]]; then
      echo "VAR_ARGS='-var-file ${var_file_path}'"
    else
      echo "VAR_ARGS=''"
    fi
  else
    # Output for copy/paste
    echo ""
    echo "# =============================="
    echo "# Terraform Arguments"
    echo "# =============================="
    echo ""
    echo "# Environment:"
    echo "#   AWS_ENV=$AWS_ENV"
    echo "#   AWS_PROFILE=$AWS_PROFILE"
    echo "#   TF_KEY=$TF_KEY"
    echo "#   TF_BUCKET=$TF_BUCKET"
    if [[ -n "$var_file_path" ]]; then
      echo "#   VAR_FILE=$var_file_path"
    else
      echo "#   VAR_FILE=(not found)"
    fi
    echo ""
    echo "# Terraform init:"
    echo "terraform init \\"
    echo "  -backend-config=\"bucket=${TF_BUCKET_PREFIX}-tfstate-${AWS_ENV}\" \\"
    echo "  -backend-config=\"key=${TF_KEY}/terraform.tfstate\" \\"
    echo "  -backend-config=\"region=us-east-1\" \\"
    echo "  -backend-config=\"dynamodb_table=tfstate_${AWS_ENV}\""
    echo ""
    if [[ -n "$var_file_path" ]]; then
      echo "# Terraform plan/apply/destroy:"
      echo "terraform <command> -var-file \"${var_file_path}\""
      echo ""
      echo "# Terraform import:"
      echo "terraform import -var-file \"${var_file_path}\" <address> <id>"
    else
      echo "# ⚠️  No tfvars file found (env-${AWS_ENV}.tfvars)"
      echo "# Terraform plan/apply/destroy:"
      echo "terraform <command>"
    fi
    echo ""
    echo "# For eval usage: tia args --eval"
    echo ""
  fi
}

cmd_apply() {
  perform_safety_check
  
  # Check for var file
  if [[ -z "$var_file_path" ]]; then
    echo -e "\n❌ Error: Could not find ${var_file} in current or parent directory"
    exit 1
  fi
  
  # Prompt for parent directory var file
  if [[ "$var_file_path" == "../${var_file}" ]]; then
    echo -e "\n⚠️  Note: Using tfvars file from parent directory: ../${var_file}"
    echo -n "Continue with parent directory tfvars file? (y/N): "
    read parent_confirm
    if [[ ! $parent_confirm == [yY] ]]; then
      echo "❌ Operation canceled."
      exit 1
    fi
  fi

  # Review settings
  echo -e "\n🔍 Review the following settings:"
  echo "AWS_ENV: $AWS_ENV"
  echo "AWS_PROFILE: $AWS_PROFILE"
  echo "TF_KEY: $TF_KEY"
  echo "TF_BUCKET: $TF_BUCKET"
  echo "TFVARS File: $var_file_path"
  echo "Action: terraform apply"
  echo -e "-----------------------------------\n"
  echo -n "Proceed with these settings? (y/N): "
  read confirm

  if [[ $confirm == [yY] ]]; then
    if [[ $skip_init == false ]]; then
      do_init
    else
      echo "Skipping Terraform init (--no-init mode)."
    fi

    echo "Applying Terraform configuration..."
    build_var_args
    run_and_echo terraform apply "${VAR_ARGS[@]}"
    echo "✅ Terraform apply complete."
  else
    echo "❌ Operation canceled."
  fi
}

cmd_destroy() {
  perform_safety_check
  
  # Check for var file
  if [[ -z "$var_file_path" ]]; then
    echo -e "\n❌ Error: Could not find ${var_file} in current or parent directory"
    exit 1
  fi
  
  # Prompt for parent directory var file
  if [[ "$var_file_path" == "../${var_file}" ]]; then
    echo -e "\n⚠️  Note: Using tfvars file from parent directory: ../${var_file}"
    echo -n "Continue with parent directory tfvars file? (y/N): "
    read parent_confirm
    if [[ ! $parent_confirm == [yY] ]]; then
      echo "❌ Operation canceled."
      exit 1
    fi
  fi

  # Review settings with extra warning for destroy
  echo -e "\n🔍 Review the following settings:"
  echo "AWS_ENV: $AWS_ENV"
  echo "AWS_PROFILE: $AWS_PROFILE"
  echo "TF_KEY: $TF_KEY"
  echo "TF_BUCKET: $TF_BUCKET"
  echo "TFVARS File: $var_file_path"
  printf "Action: \033[1;31mterraform destroy\033[0m\n"
  echo -e "-----------------------------------\n"
  printf "\033[1;31m⚠️  WARNING: This will DESTROY resources!\033[0m\n"
  echo -n "Proceed with DESTROY? (y/N): "
  read confirm

  if [[ $confirm == [yY] ]]; then
    if [[ $skip_init == false ]]; then
      do_init
    else
      echo "Skipping Terraform init (--no-init mode)."
    fi

    echo "Destroying Terraform resources..."
    build_var_args
    run_and_echo terraform destroy "${VAR_ARGS[@]}"
    echo "✅ Terraform destroy complete."
  else
    echo "❌ Operation canceled."
  fi
}

cmd_plan() {
  perform_safety_check
  
  # Check for var file
  if [[ -z "$var_file_path" ]]; then
    echo -e "\n❌ Error: Could not find ${var_file} in current or parent directory"
    exit 1
  fi
  
  # Prompt for parent directory var file
  if [[ "$var_file_path" == "../${var_file}" ]]; then
    echo -e "\n⚠️  Note: Using tfvars file from parent directory: ../${var_file}"
    echo -n "Continue with parent directory tfvars file? (y/N): "
    read parent_confirm
    if [[ ! $parent_confirm == [yY] ]]; then
      echo "❌ Operation canceled."
      exit 1
    fi
  fi

  # Review settings
  echo -e "\n🔍 Review the following settings:"
  echo "AWS_ENV: $AWS_ENV"
  echo "AWS_PROFILE: $AWS_PROFILE"
  echo "TF_KEY: $TF_KEY"
  echo "TF_BUCKET: $TF_BUCKET"
  echo "TFVARS File: $var_file_path"
  echo "Action: terraform plan"
  echo -e "-----------------------------------\n"
  echo -n "Proceed with these settings? (y/N): "
  read confirm

  if [[ $confirm == [yY] ]]; then
    if [[ $skip_init == false ]]; then
      do_init
    else
      echo "Skipping Terraform init (--no-init mode)."
    fi

    echo "Running Terraform plan..."
    build_var_args
    run_and_echo terraform plan "${VAR_ARGS[@]}"
    echo "✅ Terraform plan complete."
  else
    echo "❌ Operation canceled."
  fi
}

cmd_init() {
  perform_safety_check
  
  # Review settings
  echo -e "\n🔍 Review the following settings:"
  echo "AWS_ENV: $AWS_ENV"
  echo "AWS_PROFILE: $AWS_PROFILE"
  echo "TF_KEY: $TF_KEY"
  echo "TF_BUCKET: $TF_BUCKET"
  echo "Action: terraform init only"
  echo -e "-----------------------------------\n"
  echo -n "Proceed with these settings? (y/N): "
  read confirm

  if [[ $confirm == [yY] ]]; then
    do_init
    echo "✅ Terraform init complete."
  else
    echo "❌ Operation canceled."
  fi
}

cmd_import() {
  local address="$1"
  local id="$2"
  
  if [[ -z "$address" || -z "$id" ]]; then
    echo "❌ Error: import requires <address> and <id>"
    echo "Usage: tia import <address> <id>"
    echo "Example: tia import aws_s3_bucket.mybucket my-bucket-name"
    exit 1
  fi

  perform_safety_check
  
  # Check for var file (needed to avoid prompts)
  if [[ -z "$var_file_path" ]]; then
    echo -e "\n❌ Error: Could not find ${var_file} in current or parent directory"
    exit 1
  fi

  # Review settings
  echo -e "\n🔍 Review the following settings:"
  echo "AWS_ENV: $AWS_ENV"
  echo "AWS_PROFILE: $AWS_PROFILE"
  echo "TF_KEY: $TF_KEY"
  echo "TF_BUCKET: $TF_BUCKET"
  echo "TFVARS File: $var_file_path"
  echo "Action: terraform import"
  echo "  Address: $address"
  echo "  ID: $id"
  echo -e "-----------------------------------\n"
  echo -n "Proceed with import? (y/N): "
  read confirm

  if [[ $confirm == [yY] ]]; then
    if [[ $skip_init == false ]]; then
      do_init
    else
      echo "Skipping Terraform init (--no-init mode)."
    fi

    echo "Importing resource..."
    build_var_args
    run_and_echo terraform import "${VAR_ARGS[@]}" "$address" "$id"
    echo "✅ Terraform import complete."
  else
    echo "❌ Operation canceled."
  fi
}

cmd_state() {
  local state_cmd="$1"
  shift 2>/dev/null || true
  
  case "$state_cmd" in
    list)
      perform_safety_check
      echo -e "\n🔍 Running terraform state list"
      echo "AWS_ENV: $AWS_ENV"
      echo "AWS_PROFILE: $AWS_PROFILE"
      echo "TF_KEY: $TF_KEY"
      echo -e "-----------------------------------\n"
      
      if [[ $skip_init == false && ! -d ".terraform" ]]; then
        echo "⚠️  No .terraform directory found. Running init first..."
        do_init
      fi
      
      build_var_args
      if [[ ${#VAR_ARGS[@]} -gt 0 ]]; then
        run_and_echo terraform state list "${VAR_ARGS[@]}"
      else
        run_and_echo terraform state list
      fi
      ;;
      
    show)
      local address="$1"
      if [[ -z "$address" ]]; then
        echo "❌ Error: state show requires <address>"
        echo "Usage: tia state show <address>"
        exit 1
      fi
      
      perform_safety_check
      echo -e "\n🔍 Running terraform state show"
      echo "AWS_ENV: $AWS_ENV"
      echo "AWS_PROFILE: $AWS_PROFILE"
      echo "TF_KEY: $TF_KEY"
      echo "Address: $address"
      echo -e "-----------------------------------\n"
      
      if [[ $skip_init == false && ! -d ".terraform" ]]; then
        echo "⚠️  No .terraform directory found. Running init first..."
        do_init
      fi
      
      run_and_echo terraform state show "$address"
      ;;
      
    rm)
      local address="$1"
      if [[ -z "$address" ]]; then
        echo "❌ Error: state rm requires <address>"
        echo "Usage: tia state rm <address>"
        exit 1
      fi
      
      perform_safety_check
      echo -e "\n🔍 Review state rm operation:"
      echo "AWS_ENV: $AWS_ENV"
      echo "AWS_PROFILE: $AWS_PROFILE"
      echo "TF_KEY: $TF_KEY"
      printf "Action: \033[1;31mterraform state rm\033[0m\n"
      echo "Address: $address"
      echo -e "-----------------------------------\n"
      printf "\033[1;31m⚠️  WARNING: This will remove the resource from state!\033[0m\n"
      echo -n "Proceed with state rm? (y/N): "
      read confirm
      
      if [[ $confirm == [yY] ]]; then
        if [[ $skip_init == false && ! -d ".terraform" ]]; then
          echo "⚠️  No .terraform directory found. Running init first..."
          do_init
        fi
        
        run_and_echo terraform state rm "$address"
        echo "✅ State rm complete."
      else
        echo "❌ Operation canceled."
      fi
      ;;
      
    mv)
      local src="$1"
      local dst="$2"
      if [[ -z "$src" || -z "$dst" ]]; then
        echo "❌ Error: state mv requires <source> and <destination>"
        echo "Usage: tia state mv <source> <destination>"
        exit 1
      fi
      
      perform_safety_check
      echo -e "\n🔍 Review state mv operation:"
      echo "AWS_ENV: $AWS_ENV"
      echo "AWS_PROFILE: $AWS_PROFILE"
      echo "TF_KEY: $TF_KEY"
      echo "Action: terraform state mv"
      echo "  From: $src"
      echo "  To: $dst"
      echo -e "-----------------------------------\n"
      echo -n "Proceed with state mv? (y/N): "
      read confirm
      
      if [[ $confirm == [yY] ]]; then
        if [[ $skip_init == false && ! -d ".terraform" ]]; then
          echo "⚠️  No .terraform directory found. Running init first..."
          do_init
        fi
        
        run_and_echo terraform state mv "$src" "$dst"
        echo "✅ State mv complete."
      else
        echo "❌ Operation canceled."
      fi
      ;;
      
    *)
      echo "❌ Unknown state command: $state_cmd"
      echo "Available state commands: list, show, rm, mv"
      exit 1
      ;;
  esac
}

# ==============================
# Main dispatch
# ==============================

case "$SUBCOMMAND" in
  apply)
    cmd_apply
    ;;
  destroy)
    cmd_destroy
    ;;
  plan)
    cmd_plan
    ;;
  init)
    cmd_init
    ;;
  import)
    cmd_import "$@"
    ;;
  state)
    cmd_state "$@"
    ;;
  args)
    cmd_args "$@"
    ;;
  *)
    echo "❌ Unknown command: $SUBCOMMAND"
    echo "Use 'tia --help' for usage information."
    exit 1
    ;;
esac
