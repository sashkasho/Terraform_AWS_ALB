output "server_ip" {
    value = aws_instance.test_server[*].public_ip
}
output "ALB_DNS" {
    value = "http://${aws_alb.test-alb.dns_name}"
}