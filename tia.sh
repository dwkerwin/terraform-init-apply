#!/bin/zsh

# Default values for optional flags
apply_only=false

# Parse optional flags
while getopts "a" opt; do
  case $opt in
    a) apply_only=true ;;
    *) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

# Check for required environment variables
missing_vars=()
[[ -z "$AWS_ENV" ]] && missing_vars+=("AWS_ENV")
[[ -z "$AWS_PROFILE" ]] && missing_vars+=("AWS_PROFILE")
[[ -z "$TF_KEY" ]] && missing_vars+=("TF_KEY")

if [[ ${#missing_vars[@]} -gt 0 ]]; then
  echo -e "\n❌ Missing required environment variables:"
  for var in "${missing_vars[@]}"; do
    echo "  - $var"
  done
  echo -e "\nPlease export the missing variables and try again."
  exit 1
fi

# Determine the bucket prefix based on the profile
PROFILE_PREFIX=${AWS_PROFILE%%-*} # Extract the first part of AWS_PROFILE

if [[ $PROFILE_PREFIX == aug* ]]; then
    TF_BUCKET_PREFIX="augmetrics"
elif [[ $PROFILE_PREFIX == bsa* ]]; then
    TF_BUCKET_PREFIX="bsa"
elif [[ $PROFILE_PREFIX == vm* ]]; then
    TF_BUCKET_PREFIX="vm"
else
    echo "Error: Unrecognized profile prefix '$PROFILE_PREFIX'. Please use a supported profile."
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
        terraform init \
            -backend-config="bucket=${TF_BUCKET_PREFIX}-tfstate-${AWS_ENV}" \
            -backend-config="key=${TF_KEY}/terraform.tfstate" \
            -backend-config="region=us-east-1" \
            -backend-config="dynamodb_table=tfstate_${AWS_ENV}"
    else
        echo "Skipping Terraform init due to apply-only mode (-a)."
    fi

    # Apply Terraform configuration
    echo "Applying Terraform configuration..."
    terraform apply -var-file="${var_file_path}"

    echo "✅ Terraform init and apply complete."
else
    echo "❌ Operation canceled."
fi
