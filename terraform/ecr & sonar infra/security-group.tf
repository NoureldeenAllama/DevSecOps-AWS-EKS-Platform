resource "aws_security_group" "sonarqube" {

  name        = "sonarqube-sg"
  description = "Security Group for SonarQube"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"

    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "SonarQube"

    from_port = 9000
    to_port   = 9000
    protocol  = "tcp"

    cidr_blocks = ["0.0.0.0/0"]
  }
 
  egress {

    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sonarqube-sg"
  }
}