# Terraform-init-apply (tia)

A script to streamline Terraform workflows with consistent initialization, apply, destroy, state management, and more.

## Quick Reference

```bash
# Core commands
tia                           # init + apply (default)
tia apply                     # init + apply
tia plan                      # init + plan
tia destroy                   # init + destroy
tia init                      # init only

# Skip init (use existing .terraform)
tia -a apply                  # apply only
tia --no-init destroy         # destroy only

# Import resources
tia import aws_s3_bucket.foo my-bucket-name

# State operations
tia state list                # list resources in state
tia state show <address>      # show a resource
tia state rm <address>        # remove from state
tia state mv <src> <dst>      # move/rename in state

# Get args for manual commands
tia args                      # copy/paste format
tia args --eval               # for eval $(tia args --eval)

# Help & version
tia --help                    # show full help
tia --version                 # show version
```

## Motivation

In my Terraform module workflow, I always use the following environment variables:

- **`AWS_ENV`**: Specifies the AWS environment (e.g., `dev`, `prod`).
- **`AWS_PROFILE`**: Specifies the AWS CLI profile to use for authentication.
- **`TF_KEY`**: Specifies the unique Terraform state key for the module. Can be provided as an environment variable OR as a local file named `TF_KEY` (file takes precedence).

Managing these variables manually and ensuring consistent application of Terraform configurations outside of CI/CD can be time-consuming. This script simplifies the process by:

- Checking for the existence of these required environment variables before proceeding.
- Reinitializing Terraform safely by removing existing state to avoid conflicts.
- Prompting for a review of settings before continuing.
- Supporting multiple operations: apply, destroy, plan, import, and state management.

This tool is designed for use when working on Terraform modules locally, ensuring a faster and more streamlined workflow.

## Installation

1. Clone this repository into your `~/bin` directory:

```bash
git clone https://github.com/dwkerwin/terraform-init-apply.git ~/bin/terraform-init-apply
```

2. Add the repository to your PATH by including the following line in your ~/.zshrc file:

```bash
export PATH="$HOME/bin/terraform-init-apply:$PATH"
```

3. Reload your terminal or source your ~/.zshrc file to apply the changes:

```bash
source ~/.zshrc
```

4. Ensure the script is executable and create a symlink so the script can be called without the .sh extension:

```bash
chmod +x ~/bin/terraform-init-apply/tia.sh
ln -s ~/bin/terraform-init-apply/tia.sh ~/bin/terraform-init-apply/tia
```

## Configuration

To add or modify AWS profile mappings, edit the configuration maps at the top of `tia.sh`:

- **`PROFILE_BUCKET_PREFIX_MAP`**: Maps profile prefixes (e.g., `aug`, `vm`) to S3 bucket prefixes
- **`PROFILE_ALLOWED_DIR_PREFIXES_MAP`**: Maps profile prefixes to allowed directory names under `~/devel/`

Example:
```bash
PROFILE_BUCKET_PREFIX_MAP=(
  aug "augmetrics"
  vm  "vm"
  newco "newcompany"
)

PROFILE_ALLOWED_DIR_PREFIXES_MAP=(
  aug "aug adw"          # aug profiles work in ~/devel/aug/ or ~/devel/adw/
  vm  "vm"               # vm profiles work in ~/devel/vm/
  newco "newco nc"       # newco profiles work in ~/devel/newco/ or ~/devel/nc/
)
```

## Usage

Navigate to a directory containing your Terraform configuration and run the script:

```bash
tia
```

### Example Workflow

1. The script will review the required configuration (AWS_ENV, AWS_PROFILE, and TF_KEY) and ensure they are available. TF_KEY can be provided either as an environment variable or as a local file named `TF_KEY` - the file takes precedence if both exist.

2. It will display the current settings for your review:

```bash
🔍 Review the following settings:
AWS_ENV: dev
AWS_PROFILE: augdev
TF_KEY: my-module
TF_BUCKET: s3://augmetrics-tfstate-dev
TFVARS File: ./env-dev.tfvars
Action: terraform apply
-----------------------------------

Proceed with these settings? (y/N):
```

3. If confirmed, the script will:

- Remove the .terraform directory to ensure a clean initialization (unless `--no-init` is used).
- Reinitialize Terraform with the correct backend configuration.
- Run the requested terraform command (apply, destroy, plan, etc.).

### Commands

| Command | Description |
|---------|-------------|
| `tia` or `tia apply` | Initialize and apply |
| `tia destroy` | Initialize and destroy (with extra warning) |
| `tia plan` | Initialize and plan |
| `tia init` | Initialize only |
| `tia import <addr> <id>` | Import existing resource into state |
| `tia state list` | List resources in state |
| `tia state show <addr>` | Show a resource in state |
| `tia state rm <addr>` | Remove a resource from state |
| `tia state mv <src> <dst>` | Move/rename a resource in state |
| `tia args` | Output computed arguments for manual use |
| `tia args --eval` | Output arguments in eval-able format |

### Options

| Option | Description |
|--------|-------------|
| `-a`, `--no-init` | Skip terraform init (use existing .terraform) |
| `-V`, `--version` | Show version |
| `-h`, `--help` | Show help |

### Using `tia args`

When you need to run a terraform command that `tia` doesn't directly support, use `tia args` to get the computed arguments:

```bash
$ tia args

# ==============================
# Terraform Arguments
# ==============================

# Environment:
#   AWS_ENV=dev
#   AWS_PROFILE=augdev
#   TF_KEY=my-module
#   TF_BUCKET=s3://augmetrics-tfstate-dev
#   VAR_FILE=./env-dev.tfvars

# Terraform init:
terraform init \
  -backend-config="bucket=augmetrics-tfstate-dev" \
  -backend-config="key=my-module/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=tfstate_dev"

# Terraform plan/apply/destroy:
terraform <command> -var-file "./env-dev.tfvars"

# Terraform import:
terraform import -var-file "./env-dev.tfvars" <address> <id>

# For eval usage: tia args --eval
```

For scripting, use the `--eval` flag:

```bash
eval $(tia args --eval)
terraform plan $VAR_ARGS
```

## TF_KEY Configuration

The `TF_KEY` parameter can be provided in two ways, with local files taking precedence:

1. **Local file (preferred)**: Create a file named `TF_KEY` in your project directory containing the key on a single line:
   ```bash
   echo "my-project-terraform-key" > TF_KEY
   ```

2. **Environment variable (fallback)**: Export the traditional environment variable:
   ```bash
   export TF_KEY="my-project-terraform-key"
   ```

When both exist, the local `TF_KEY` file takes precedence. This allows you to:
- Commit project-specific Terraform keys to your repositories
- Override global environment settings on a per-project basis
- Maintain backward compatibility with existing workflows

The script will display which source is being used:
- `🔑 Using TF_KEY from local file: ./TF_KEY`
- `🔑 Using TF_KEY from environment variable`

## Safety Check: AWS profile vs directory prefix

When the current working directory is under `~/devel/`, the script performs a safety check to help avoid mistakes across accounts. It compares the account prefix suggested by `AWS_PROFILE` (e.g., `vm`, `aug`, `bsa`) with the first directory segment under `~/devel/` (e.g., `~/devel/vm/...`). If they don't match, it prints a red warning and prompts you to confirm before continuing. This check is skipped when you are outside of `~/devel/`.

If a mismatch is detected, the script will prompt:

```text
Are you sure you want to continue? (y/N):
```

Respond with `y` to continue, any other response cancels the run.

## Testing

Run the test suite to verify the script works correctly:

```bash
./test_tia.sh
```

The tests validate argument parsing, profile resolution, error handling, and output generation without executing any real terraform commands.

## Version

Check the installed version:

```bash
tia --version
```
