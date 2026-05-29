resource "random_password" "db" {
  length  = 20
  special = false
}
resource "aws_secretsmanager_secret" "db" {
  name = "mds-tools/prod/rds-master"
}
resource "aws_secretsmanager_secret_version" "db" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({ username = "mdsmaster", password = random_password.db.result })
}
resource "aws_db_subnet_group" "rds" {
  name       = "mds-tools-db-subnets"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}
resource "aws_db_instance" "pg" {
  identifier              = "mds-tools-db"
  engine                  = "postgres"
  engine_version          = "16"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  db_subnet_group_name    = aws_db_subnet_group.rds.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  username                = "mdsmaster"
  password                = random_password.db.result
  skip_final_snapshot     = true
  publicly_accessible     = false
  backup_retention_period = 1 # snapshots on; bump + Multi-AZ for the HA/DR talking point
  tags                    = { Name = "mds-tools-db", Service = "shared" }
}