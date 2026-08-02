resource "aws_instance" "sonarqube" {
  ami           = var.ami_id
  instance_type = var.instance_type

  subnet_id = var.public_subnet_id

  key_name = var.key_name

  vpc_security_group_ids = [
    aws_security_group.sonarqube.id
  ]

  associate_public_ip_address = true

  root_block_device {

    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = "SonarQube"
  }
}