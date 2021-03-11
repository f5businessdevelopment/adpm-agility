output "a_bigip_management_address" {
  value = "https://${module.bigip.0.mgmtPublicIP}:8443"
}

output "d_application_address" {
  description = "Public endpoint for load balancing external app"
  value       = "https://${azurerm_public_ip.alb_public_ip.ip_address}"
}

output "e_consul_public_address" {
   value = "http://${azurerm_public_ip.mgmt_public_ip.ip_address}:8500"
 }

output "f_elk_public_address" {
   value = "http://${azurerm_public_ip.elk_public_ip.ip_address}"
}

output Student_ID {
   value = local.student_id
}

