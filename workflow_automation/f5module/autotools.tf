# Setup Onboarding scripts
data "template_file" "init_file" {
  template = file("${path.module}/onboard.tpl")

  vars = {
    admin_username = var.f5_username
    admin_password = local.upass
    DO_URL         = var.doPackageUrl
    AS3_URL        = var.as3PackageUrl
    TS_URL         = var.tsPackageUrl
    libs_dir       = var.libs_dir
    onboard_log    = var.onboard_log
    DO_Document    = data.template_file.vm01_do_json.rendered
    AS3_Document   = data.template_file.as3_json.rendered
    TS_Document    = data.template_file.ts_json.rendered
  }
}

data "template_file" "vm01_do_json" {
  template = file("${path.module}/do.json")

  vars = {
    hostname        = local.hostname
    local_selfip       = "-external-self-address-"
    gateway            = var.ext_gw
    dns_server         = var.dns_server
    ntp_server         = var.ntp_server
    timezone           = var.timezone
  }
}

data "template_file" "as3_json" {
  depends_on = [null_resource.azure_cli_add]
  template = file("${path.module}/as3.json")
  vars = {
    backendvm_ip    = var.backend01ext
    web_pool        = "myapp-${var.app}"
    app_name        = var.app_name
    local_selfip    = data.consul_keys.vip.var.vip_address
  }
}

  data "template_file" "ts_json" {
  template = file("${path.module}/ts.json")

  vars = {
    region      = data.azurerm_resource_group.bigiprg.location
    logStashIP  = var.logStashIP
    logStashPort = var.logStashPort
  }
}