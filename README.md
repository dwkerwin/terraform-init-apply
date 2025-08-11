Here’s a complete README.md for your terraform-init-applies Git repository:

# Terraform-init-apply

A simple script to streamline applying Terraform configurations in a consistent way based on a prescriptive Terraform module workflow. This tool ensures proper initialization, re-initialization, and application of Terraform modules using standardized environment variables.

## Motivation

In my Terraform module workflow, I always use the following environment variables:

- **`AWS_ENV`**: Specifies the AWS environment (e.g., `dev`, `prod`).
- **`AWS_PROFILE`**: Specifies the AWS CLI profile to use for authentication.
- **`TF_KEY`**: Specifies the unique Terraform state key for the module.

Managing these variables manually and ensuring consistent application of Terraform configurations outside of CI/CD can be time-consuming. This script simplifies the process by:

- Checking for the existence of these required environment variables before proceeding.
- Reinitializing Terraform safely by removing existing state to avoid conflicts.
- Prompting for a review of settings before continuing.
- Applying Terraform configurations in an efficient and repeatable manner.

This tool is designed for use when working on Terraform modules locally, ensuring a faster and more streamlined workflow.

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

## Usage

Navigate to a directory containing your Terraform configuration and run the script:

```bash
tia
```

Example Workflow

1.	The script will review the required environment variables (AWS_ENV, AWS_PROFILE, and TF_KEY) and ensure they are set.
2.	It will display the current settings for your review:

```bash
🔍 Review the following settings:
AWS_ENV: dev
AWS_PROFILE: augdev
TF_KEY: my-module
TF_BUCKET: s3://augmetrics-tfstate-dev
-----------------------------------
Proceed with these settings? (y/N):
```


3.	If confirmed, the script will:

- Remove the .terraform directory to ensure a clean initialization.
- Reinitialize Terraform with the correct backend configuration.
- Apply the Terraform configuration with the appropriate variable file.

Version

Check the installed version:

```bash
tia --version
```

Safety Check: AWS profile vs directory prefix

When the current working directory is under `~/devel/`, the script performs a safety check to help avoid mistakes across accounts. It compares the account prefix suggested by `AWS_PROFILE` (e.g., `vm`, `aug`, `bsa`) with the first directory segment under `~/devel/` (e.g., `~/devel/vm/...`). If they don't match, it prints a red warning and prompts you to confirm before continuing. This check is skipped when you are outside of `~/devel/`.

If a mismatch is detected, the script will prompt:

```text
Are you sure you want to continue? (y/N):
```

Respond with `y` to continue, any other response cancels the run.

Flags

- `-a`: Skips terraform init and applies the configuration directly.

Example Commands

- Run the script normally:

```bash
tia
```

- Apply only (skip terraform init):

```bash
tia -a
```
