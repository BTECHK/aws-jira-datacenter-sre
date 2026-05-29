resource "aws_security_group" "proxy" {
  name   = "mds-tools-sg-proxy"
  vpc_id = aws_vpc.main.id
  tags   = { Name = "mds-tools-sg-proxy" }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.my_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "app" {
  name   = "mds-tools-sg-app"
  vpc_id = aws_vpc.main.id
  tags   = { Name = "mds-tools-sg-app" }
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.proxy.id] # Redmine + Gitea
  }
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.proxy.id] # XWiki/Tomcat
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "rds" {
  name   = "mds-tools-sg-rds"
  vpc_id = aws_vpc.main.id
  tags   = { Name = "mds-tools-sg-rds" }
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}