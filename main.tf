data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_subnet" "firstsub" {
  id = "${var.lambda_subnets[0]}"
}

resource "aws_iam_role" "lambda_rotation" {
  name = "${var.name}-rotation-lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy_attachment" "lambdabasic" {
  name       = "${var.name}-lambdabasic"
  roles      = ["${aws_iam_role.lambda_rotation.name}"]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "SecretsManagerRDSMySQLRotationSingleUserRolePolicy" {
  statement {
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DetachNetworkInterface",
    ]

    resources = ["*"]
  }

  statement {
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecretVersionStage",
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:*",
    ]
  }

  statement {
    actions   = ["secretsmanager:GetRandomPassword"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "SecretsManagerRDSMySQLRotationSingleUserRolePolicy" {
  name   = "${var.name}-SecretsManagerRDSMySQLRotationSingleUserRolePolicy"
  path   = "/"
  policy = "${data.aws_iam_policy_document.SecretsManagerRDSMySQLRotationSingleUserRolePolicy.json}"
}

resource "aws_iam_policy_attachment" "SecretsManagerRDSMySQLRotationSingleUserRolePolicy" {
  name       = "${var.name}-SecretsManagerRDSMySQLRotationSingleUserRolePolicy"
  roles      = ["${aws_iam_role.lambda_rotation.name}"]
  policy_arn = "${aws_iam_policy.SecretsManagerRDSMySQLRotationSingleUserRolePolicy.arn}"
}

resource "aws_security_group" "lambda" {
  vpc_id = "${data.aws_subnet.firstsub.vpc_id}"
  name   = "${var.name}-Lambda-SecretManager"

  tags {
    Name = "${var.name}-Lambda-SecretManager"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

variable "filename" {
  default = "rotate-code-mysql"
}

resource "aws_lambda_function" "rotate-code-mysql" {
  filename         = "${path.module}/${var.filename}.zip"
  function_name    = "${var.name}-${var.filename}"
  role             = "${aws_iam_role.lambda_rotation.arn}"
  handler          = "lambda_function.lambda_handler"
  source_code_hash = "${base64sha256(file("${path.module}/${var.filename}.zip"))}"
  runtime          = "python2.7"

  vpc_config {
    subnet_ids         = ["${var.lambda_subnets}"]
    security_group_ids = ["${aws_security_group.lambda.id}"]
  }

  timeout     = 30
  description = "Conducts an AWS SecretsManager secret rotation for RDS MySQL using single user rotation scheme"

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${data.aws_region.current.name}.amazonaws.com" #https://docs.aws.amazon.com/general/latest/gr/rande.html#asm_region
    }
  }
}

resource "aws_lambda_permission" "allow_secret_manager_call_Lambda" {
  function_name = "${aws_lambda_function.rotate-code-mysql.function_name}"
  statement_id  = "AllowExecutionSecretManager"
  action        = "lambda:InvokeFunction"
  principal     = "secretsmanager.amazonaws.com"
}

resource "aws_kms_key" "secret" {
  description         = "Key for secret ${var.name}"
  enable_key_rotation = true

  policy = <<POLICY
{
  "Id": "key-consolepolicy-3",
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        ]
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow use of the key",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "${aws_iam_role.lambda_rotation.arn}",
          "${data.aws_caller_identity.current.arn}"
        ]
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Allow attachment of persistent resources",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "${aws_iam_role.lambda_rotation.arn}"
        ]
      },
      "Action": [
        "kms:CreateGrant",
        "kms:ListGrants",
        "kms:RevokeGrant"
      ],
      "Resource": "*",
      "Condition": {
        "Bool": {
          "kms:GrantIsForAWSResource": "true"
        }
      }
    }
  ]
}
POLICY
}

resource "aws_kms_alias" "secret" {
  name          = "alias/${var.name}"
  target_key_id = "${aws_kms_key.secret.key_id}"
}

resource "aws_secretsmanager_secret" "secret" {
  description         = "${var.secret_description}"
  kms_key_id          = "${aws_kms_key.secret.key_id}"
  name                = "${var.name}"
  rotation_lambda_arn = "${aws_lambda_function.rotate-code-mysql.arn}"

  rotation_rules {
    automatically_after_days = "${var.rotation_days}"
  }

  recovery_window_in_days = "${var.force_delete == 1 ? 0 : 7}"

  tags = "${var.tags}"
}

resource "aws_secretsmanager_secret_version" "secret" {
  lifecycle {
    ignore_changes = [
      "secret_string",
    ]
  }

  secret_id = "${aws_secretsmanager_secret.secret.id}"

  secret_string = <<EOF
{
  "username": "${var.mysql_username}",
  "engine": "mysql",
  "dbname": "${var.mysql_dbname}",
  "host": "${var.mysql_host}",
  "password": "${var.mysql_password}",
  "port": ${var.mysql_port},
  "dbInstanceIdentifier": "${var.mysql_dbInstanceIdentifier}"
}
EOF
}
