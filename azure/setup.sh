#!/bin/bash

if ! [[ "$1" =~ ^(local|build|deploy|destroy|cleanup)$ ]]; then
    printf "=> No valid target given, possible values: local|build|deploy|destroy\n\n"
    exit 1
fi

build() {
    for STUDENT in $(cat students.txt); do
        export STUDENT

        cat << 'EOF' > $STUDENT.tf.tmp
resource "random_password" "$STUDENT-pass" {
  length           = 12
  special          = true
  override_special = "_%@"
}

resource "azuread_user" "$STUDENT-user" {
  user_principal_name = "$STUDENT@acend.onmicrosoft.com"
  display_name        = "$STUDENT"
  password            = random_password.$STUDENT-pass.result
}

resource "azuread_group_member" "$STUDENT-group" {
  group_object_id  = data.azuread_group.students.id
  member_object_id = azuread_user.$STUDENT-user.id
}

output "$STUDENT-login" {
  description = "display username"
  value       = "${azuread_user.$STUDENT-user.user_principal_name} => ${random_password.$STUDENT-pass.result}"
  sensitive   = true
}
EOF

        cat $STUDENT.tf.tmp | envsubst > $STUDENT.tf
        rm $STUDENT.tf.tmp

    done
}

cleanup() {
  echo "INFO: cleanup trash"
  test -d .terraform/ && rm -rf .terraform/
  test -f .terraform.lock.hcl && rm .terraform.lock.hcl
  test -f terraform.tfstate && rm terraform.tfstate*
}

local() {
    trap cleanup EXIT
    trap cleanup SIGTERM
    docker run -it --rm -w $(pwd) -v $(pwd):$(pwd) acend/theia bash
}

deploy() {
    build
    if [ "$(az account show --query name -o tsv)" != "acend-lab-sub" ]; then
        az login
    fi
    terraform init
    terraform plan
    terraform apply
    for STUDENT in $(cat students.txt); do
        STUDENT=${STUDENT%@*}
	echo "$(terraform output $STUDENT-user) $(terraform output $STUDENT-pass)"
    done
}

destroy() {
    terraform destroy
    # cleanup left groups
    RGS=$(az group list --query [].name -o table | grep "rg-" | tr "\n" " ")
    for RG in $RGS; do
	echo deleting rg $RG
        az group delete --resource-group $RG -y
    done
    terraform destroy
}

"$@"

exit 0
