variable "name" {
  description = "This name will be used as prefix for all the created resources"
}

variable "secret_description" {
  description = "This field is the description for the secret manager object"
  default     = "secret manager for mysql/aurora"
}

variable "rotation_days" {
  default     = 30
  description = "How often in days the secret will be rotated"
}

variable "lambda_subnets" {
  type = "list"
}

variable "mysql_username" {}

variable "mysql_dbname" {}

variable "mysql_host" {}

variable "mysql_password" {}

variable "mysql_port" {
  default = 3306
}

variable "mysql_dbInstanceIdentifier" {
  description = "The RDS Identifier in the webconsole"
}

variable "tags" {
  type = "map"
}

/* Not yet available
variable "additional_kms_role_arn" {
  type = "list"
  default = [""]
  description = "If you want add another role of another resource to access to the kms key used to encrypt the secret"
}
*/

variable "force_delete" {
  default = 0
}
