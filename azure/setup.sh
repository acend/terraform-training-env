#!/bin/bash

# Default variable values
sync_remote_tf_state=false


usage() {
 echo "Usage: $0 [TARGET] [OPTIONS]"
 echo "Target:"
 echo " local:   run theia shell for tests"
 echo " build:   create terraform files with users"
 echo " deploy:  build and run tf init|plan|apply and output logins"
 echo " logins:  show created logins for users"
 echo " destroy: tf destroy and rg deleting with azure cli"
 echo "Options:"
 echo " -h, --help      Display this help message"
 echo " -s, --sync-remote-state   Use TF Remote State for User & Passwords"
}


# Function to handle options and arguments
handle_options() {

  if ! [[ "$1" =~ ^(local|build|deploy|logins|destroy|cleanup)$ ]]; then
      echo "=> No valid target given"
      usage
      exit 1
  fi
  
  shift

  while [ $# -gt 0 ]; do

    case $1 in
      -h | --help)
        usage
        exit 0
        ;;
      -s | --sync-remote-state)
        sync_remote_tf_state=true
        ;;
      *)
        echo "Invalid option: $1" >&2
        usage
        exit 1
        ;;
    esac
    shift
  done
}

build-with-remotestate() {

    cat << 'EOF' > students.tf

data "terraform_remote_state" "cluster" {
  backend = "s3"

  config = {
    bucket = "terraform"
    key    = "terraform.tfstate"
    region = "main"

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}

resource "azuread_user" "user" {
    count = data.terraform_remote_state.cluster.outputs.count-students

    user_principal_name = "${data.terraform_remote_state.cluster.outputs.studentname-prefix}${count.index + 1}@acend.onmicrosoft.com"
    display_name        = "${data.terraform_remote_state.cluster.outputs.studentname-prefix}${count.index + 1}"
    password            = data.terraform_remote_state.cluster.outputs.student-passwords[count.index].result
}

resource "azuread_group_member" "group" {
    count = data.terraform_remote_state.cluster.outputs.count-students


    group_object_id  = data.azuread_group.students.id
    member_object_id = azuread_user.user[count.index].id
}

EOF
}


build() {
    STUDENTS_LIST=$(grep -v '^[[:space:]]*$' students.txt | awk '{printf "\"%s\", ", $0}' | sed 's/, $//')

    cat > students.tf << EOF
locals {
  students = toset([${STUDENTS_LIST}])
}

resource "random_password" "student" {
  for_each         = local.students
  length           = 12
  special          = true
  override_special = "_%@"
}

resource "azuread_user" "student" {
  for_each = local.students

  user_principal_name = "\${each.key}@acend.onmicrosoft.com"
  display_name        = each.key
  password            = random_password.student[each.key].result
}

resource "azuread_group_member" "student" {
  for_each = local.students

  group_object_id  = data.azuread_group.students.id
  member_object_id = azuread_user.student[each.key].id
}

output "student_logins" {
  description = "Student login credentials"
  sensitive   = true
  value = {
    for s in local.students : s => "\${azuread_user.student[s].user_principal_name} => \${random_password.student[s].result}"
  }
}
EOF
}

cleanup() {
  echo "INFO: cleanup trash"
  test -d .terraform/ && rm -rf .terraform/
  test -f .terraform.lock.hcl && rm .terraform.lock.hcl
  test -f terraform.tfstate && rm terraform.tfstate*
  rm -rf student-*.tf
  rm -rf students.tf
}

run_local() {
    trap cleanup EXIT
    trap cleanup SIGTERM
    docker run -it --rm -w $(pwd) -v $(pwd):$(pwd) acend/theia bash
}

setup() {
    if [ "$(az account show --query name -o tsv)" != "acend-lab-sub" ]; then
        az login --tenant 79b79954-f1b6-4d8b-868d-7c22edee3e00
        az account set --subscription acend-lab-sub
    fi
    # azurerm 4.x requires subscription_id to be set explicitly
    export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
}

logins() {
    terraform output -json student_logins | python3 -c "import json, sys; [print(v) for v in json.load(sys.stdin).values()]"
}

deploy() {
    if [ "$sync_remote_tf_state" = true ]; then
        echo "Using existing users from k8s cluster setup"

        if [[ ! -v AWS_ACCESS_KEY_ID ]]; then
            echo "AWS_ACCESS_KEY_ID is not set"
            exit 1
        fi
        if [[ ! -v AWS_SECRET_ACCESS_KEY ]]; then
            echo "AWS_SECRET_ACCESS_KEY is not set"
            exit 1
        fi
        if [[ ! -v AWS_S3_ENDPOINT ]]; then
            echo "AWS_S3_ENDPOINT is not set"
            exit 1
        fi

        build-with-remotestate
    else
        echo "Using users defined in students.txt with random passwords"
        build
    fi
    
    setup
    terraform init
    terraform plan
    terraform apply

    if [ "$sync_remote_tf_state" = false ]; then
      logins
    fi
}



destroy() {
    setup
    # First pass: destroy Terraform-managed resources
    terraform destroy
    # Remove student-created resource groups not tracked by Terraform
    RGS=$(az group list --query [].name -o table | grep "rg-" | tr "\n" " ")
    for RG in $RGS; do
        echo "deleting rg $RG"
        az group delete --resource-group $RG -y
    done
    # Second pass: destroy any resources that depended on the deleted RGs
    terraform destroy
}

handle_options "$@"

case "$1" in
  local)   run_local ;;
  build)   build ;;
  deploy)  deploy ;;
  logins)  logins ;;
  destroy) destroy ;;
  cleanup) cleanup ;;
esac

exit 0
