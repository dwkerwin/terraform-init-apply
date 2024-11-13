#!/bin/zsh

# Default values for optional flags
apply_only=false
use_parent_directory=false

# Parse optional flags
while getopts "ap" opt; do
  case $opt in
    a) apply_only=true ;;
    p) use_parent_directory=true ;;
    *) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
  esac
done
shift $((OPTIND -1))

# Prompt for AWS_ENV with a default option
echo -n "AWS_ENV [${AWS_ENV:-'None'}]: "
read input
AWS_ENV=${input:-$AWS_ENV}
export AWS_ENV=$AWS_ENV

# Prompt for AWS_PROFILE with a default option
echo -n "AWS_PROFILE [${AWS_PROFILE:-'None'}]: "
read input
AWS_PROFILE=${input:-$AWS_PROFILE}
export AWS_PROFILE=$AWS_PROFILE

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

# Display the derived bucket prefix
echo "Bucket prefix derived as: $TF_BUCKET_PREFIX"

# Prompt for TF_KEY with a default option
echo -n "TF_KEY [${TF_KEY:-'None'}]: "
read input
TF_KEY=${input:-$TF_KEY}
export TF_KEY=$TF_KEY

# Construct the full bucket name and display it for confirmation
TF_BUCKET="s3://${TF_BUCKET_PREFIX}-tfstate-${AWS_ENV}"
echo "TF_BUCKET set to: $TF_BUCKET"

# Confirm all environment variables before proceeding
echo -e "\n🔍 Review the following settings:"
echo "AWS_ENV: $AWS_ENV"
echo "AWS_PROFILE: $AWS_PROFILE"
echo "TF_KEY: $TF_KEY"
echo "TF_BUCKET: $TF_BUCKET"
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

    # Determine var-file path based on -p flag
    var_file_prefix=""
    if [[ $use_parent_directory == true ]]; then
        var_file_prefix="../"
    fi

    # Apply Terraform configuration
    echo "Applying Terraform configuration..."
    terraform apply -var-file="${var_file_prefix}env-${AWS_ENV}.tfvars"

    echo "✅ Terraform init and apply complete."
else
    echo "❌ Operation canceled."
fi
