variable "db_password" {
  description = "Master password for the RDS database"
  type        = string
  sensitive   = true
}