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
