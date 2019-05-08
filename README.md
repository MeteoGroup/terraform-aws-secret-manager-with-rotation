This module will create all the resources to store and rotate a MySQL or Aurora password using the AWS Secrets Manager service.
It is a copy of the repo [here](https://github.com/giuseppeborgese/terraform-aws-secret-manager-with-rotation) by Giuseppe Borgese with some very small modifications.

# Prerequisites
* A VPC with private subnets and accessibilty to AWS Secrets Manager Endpoint, see below for more details.
* An RDS with MySQL or Aurora already created and reacheable from the private subnets


# Usage Example
``` hcl
module "secret-manager-with-rotation" {
  source                     = "meteogroup/terraform-aws-secret-manager-with-rotation"
  version                    = "<always choose the latest version displayed in the upper right corner of this page>"
  name                       = "PassRotation"
  rotation_days              = 10
  subnets_lambda             = ["subnet-xxxxxx", "subnet-xxxxxx"]
  mysql_username             = "my_username"
  mysql_dbname               = "my_db_name"
  mysql_host                 =  "mysqlEndpointurl.xxxxxx.eu-west-1.rds.amazonaws.com"
  mysql_password             = "dummy_password_will_we_rotated"
  mysql_dbInstanceIdentifier = "my_rds_db_identifier"
}
```

The subnets specified needs to be private and with internet access to reach the [AWS secrets manager endpoint](https://docs.aws.amazon.com/general/latest/gr/rande.html#asm_region)
You can use a NAT GW or configure your Routes with a VPC Endpoint like is described in [this guide](https://aws.amazon.com/blogs/security/how-to-connect-to-aws-secrets-manager-service-within-a-virtual-private-cloud/)


