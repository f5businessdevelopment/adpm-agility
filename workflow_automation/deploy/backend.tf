terraform {
  backend "consul" {
    address     = "3.95.15.85:8500"
    scheme      = "http"
    path        = "adpm/labs/agility/students/asdf/terraform/tfstate"
    gzip        = true
  }
}

data "terraform_remote_state" "state" {
  backend = "consul"
  config = {
    address     = "3.95.15.85:8500"
    path = "adpm/labs/agility/students/asdf/terraform/tfstate"
  }
}

locals{
    student_id  = "asdf"
    bigip_count = 1
    app_count   = 2
}