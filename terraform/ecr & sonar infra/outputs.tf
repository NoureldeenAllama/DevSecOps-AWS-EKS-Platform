output "public_ip" {
  value = aws_instance.sonarqube.public_ip
}

output "public_dns" {
  value = aws_instance.sonarqube.public_dns
}