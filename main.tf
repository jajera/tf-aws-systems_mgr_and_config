# create rg, list created resources
resource "aws_resourcegroups_group" "example" {
  name        = "tf-rg-example"
  description = "Resource group for example resources"

  resource_query {
    query = <<JSON
    {
      "ResourceTypeFilters": [
        "AWS::AllSupported"
      ],
      "TagFilters": [
        {
          "Key": "Owner",
          "Values": ["John Ajera"]
        }
      ]
    }
    JSON
  }

  tags = {
    Name  = "tf-rg-example"
    Owner = "John Ajera"
  }
}

resource "random_string" "prefix" {
  length  = 5
  special = false
  upper   = false
  lower   = true
  numeric = false
}

resource "aws_s3_bucket" "awsconfig" {
  bucket        = "${random_string.prefix.result}awsconfig"
  force_destroy = true

  tags = {
    Name  = "tf-config-example"
    Owner = "John Ajera"
  }
}

data "aws_iam_policy_document" "config_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "s3_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.awsconfig.arn,
      "${aws_s3_bucket.awsconfig.arn}/*"
    ]
  }
}

# create iam role to allow systems manager
resource "aws_iam_role" "ssm_instance_role" {
  name = "SSMInstanceRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# attach config rule
resource "aws_config_config_rule" "ec2-instance-managed-by-systems-manager" {
  name        = "ec2-instance-managed-by-systems-manager"
  description = "Checks if your Amazon EC2 instances are managed by AWS Systems Manager (SSM Agent). The rule is NON_COMPLIANT if the EC2 instance previously associated with an SSM Agent instance inventory becomes unreachable or is not managed by SSM Agent."

  source {
    owner             = "AWS"
    source_identifier = "EC2_INSTANCE_MANAGED_BY_SSM"
  }
  scope {
    compliance_resource_types = ["AWS::EC2::Instance"]
  }

  tags = {
    Name  = "tf-configrule-example"
    Owner = "John Ajera"
  }

  depends_on = [
    aws_config_configuration_recorder.example
  ]
}

resource "aws_config_config_rule" "approved-amis-by-id" {
  name        = "approved-amis-by-id"
  description = "Checks if running EC2 instances are using specified Amazon Machine Images (AMIs). Specify a list of approved AMI IDs. Running instances with AMIs that are not on this list are NON_COMPLIANT."

  source {
    owner             = "AWS"
    source_identifier = "EC2_INSTANCE_MANAGED_BY_SSM"
  }
  scope {
    compliance_resource_types = ["AWS::EC2::Instance"]
  }

  tags = {
    Name  = "tf-configrule-example"
    Owner = "John Ajera"
  }

  depends_on = [
    aws_config_configuration_recorder.example
  ]
}

# create iam role to allow config
resource "aws_iam_role" "config" {
  name               = "ConfigRole"
  assume_role_policy = data.aws_iam_policy_document.config_assume_role.json
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_iam_role_policy" "config" {
  name   = "ConfigPolicy"
  role   = aws_iam_role.config.id
  policy = data.aws_iam_policy_document.s3_assume_role.json
}

resource "aws_config_delivery_channel" "example" {
  name           = "example"
  s3_bucket_name = aws_s3_bucket.awsconfig.bucket
}

resource "aws_config_configuration_recorder" "example" {
  name     = "example"
  role_arn = aws_iam_role.config.arn
}

resource "aws_config_configuration_recorder_status" "example" {
  name       = aws_config_configuration_recorder.example.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.example]
}

# attach policies to ssm role
resource "aws_iam_role_policy_attachment" "AmazonEC2ReadOnlyAccess" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
  role       = aws_iam_role.ssm_instance_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.ssm_instance_role.name
}

resource "aws_iam_instance_profile" "ssm" {
  name = "ssm-instance-profile"
  role = aws_iam_role.ssm_instance_role.name
}

# create vpc
resource "aws_vpc" "example" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name  = "tf-vpc-example"
    Owner = "John Ajera"
  }
}

# create subnet
resource "aws_subnet" "example" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-southeast-1a"

  tags = {
    Name  = "tf-subnet-example"
    Owner = "John Ajera"
  }
}

# create ig
resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name  = "tf-ig-example"
    Owner = "John Ajera"
  }
}

# create rt
resource "aws_route_table" "example" {
  vpc_id = aws_vpc.example.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.example.id
  }

  tags = {
    Name  = "tf-rt-example"
    Owner = "John Ajera"
  }
}

# set rt association
resource "aws_route_table_association" "example" {
  subnet_id      = aws_subnet.example.id
  route_table_id = aws_route_table.example.id
}

# get image ami
data "aws_ami" "example" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# create vm
resource "aws_instance" "example" {
  ami                  = data.aws_ami.example.image_id
  instance_type        = "t2.micro"
  iam_instance_profile = aws_iam_instance_profile.ssm.name
  subnet_id            = aws_subnet.example.id

  tags = {
    Name  = "tf-instance-example"
    Owner = "John Ajera"
  }
}
