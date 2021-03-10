cd ../terraform/deploy/
terraform init && terraform destroy --auto-approve
rm -rf .terraform
rm -rf .terraform.lock.hcl

cd ../student_backend/
rm -rf .terraform
rm -rf .terraform.lock.hcl

cd ../state_setup/
terraform init && terraform destroy --auto-approve
rm -rf .terraform
rm -rf .terraform.lock.hcl
rm -rf terraform.tfstate
rm -rf terraform.tfstate.backup 

cd ../../workflow_automation/deploy/
terraform init && terraform destroy  --auto-approve
rm -rf .terraform
rm -rf .terraform.lock.hcl
rm -rf providers.tf

cd ../state_setup/
terraform init && terraform destroy -var bigip_count=1 -var app_count=2 -var student_id="1234" --auto-approve
rm -rf .terraform
rm -rf .terraform.lock.hcl
rm -rf terraform.tfstate
rm -rf terraform.tfstate.backup 





