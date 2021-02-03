output bigip_username {
  value = module.bigip.*.f5_username
}

output bigip_password {
  value = module.bigip.*.bigip_password
}

output mgmtPublicIP {
  value = module.bigip.*.mgmtPublicIP
}

output mgmtPort {
  value = module.bigip.*.mgmtPort
}

output hostname {
  value = local.hostname
}

output "alb_address" {
  description = "Public endpoint for load balancing external app"
  value       = azurerm_public_ip.alb_public_ip.ip_address
}