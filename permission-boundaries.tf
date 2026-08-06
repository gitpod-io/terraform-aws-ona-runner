locals {
  ecs_runtime_discovery_actions = [
    "ecs:DescribeClusters",
    "ecs:ListServices",
  ]

  boundary_principal_account_condition = {
    StringEquals = {
      "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
    }
  }

  # CloudFormation-generated role names contain the Gitpod, S3Access, and
  # Devcontainer fragments. The final pattern covers this module's name_prefix
  # roles while retaining the same account-local role-assumption boundary.
  boundary_assumable_role_arns = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/gitpod-*",
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*S3Access*",
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*Devcontainer*",
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.iam_role_name_prefix}-*",
  ]

  boundary_denied_sts_actions = [
    "sts:AssumeRoleWithSAML",
    "sts:AssumeRoleWithWebIdentity",
    "sts:GetFederationToken",
    "sts:GetSessionToken",
  ]

  boundary_denied_iam_write_actions = [
    "iam:Create*",
    "iam:Delete*",
    "iam:Update*",
    "iam:Upload*",
    "iam:Set*",
    "iam:Resync*",
    "iam:Reset*",
    "iam:Put*",
    "iam:Enable*",
    "iam:Detach*",
    "iam:Deactivate*",
    "iam:Attach*",
    "iam:Add*",
    "iam:Remove*",
    "iam:Change*",
  ]

  boundary_denied_runner_network_actions = [
    "ec2:CreateVpc",
    "ec2:DeleteVpc",
    "ec2:ModifyVpc*",
    "ec2:CreateDefaultVpc",
    "ec2:*VpcCidrBlock",
    "ec2:CreateSubnet",
    "ec2:DeleteSubnet",
    "ec2:ModifySubnet*",
    "ec2:CreateDefaultSubnet",
    "ec2:*SubnetCidrBlock",
    "ec2:CreateRoute",
    "ec2:DeleteRoute",
    "ec2:ReplaceRoute",
    "ec2:CreateRouteTable",
    "ec2:DeleteRouteTable",
    "ec2:AssociateRouteTable",
    "ec2:DisassociateRouteTable",
    "ec2:ReplaceRouteTableAssociation",
    "ec2:*VgwRoutePropagation",
    "ec2:Create*Gateway*",
    "ec2:Delete*Gateway*",
    "ec2:Attach*Gateway*",
    "ec2:Detach*Gateway*",
    "ec2:Modify*Gateway*",
    "ec2:CreateVpcEndpoint*",
    "ec2:DeleteVpcEndpoint*",
    "ec2:ModifyVpcEndpoint*",
    "ec2:*VpcEndpointConnections",
    "ec2:*VpcPeeringConnection",
    "ec2:ModifyVpcPeeringConnectionOptions",
    "ec2:*Dhcp*",
    "ec2:*NetworkAcl*",
    "ec2:*Vpn*",
    "ec2:*CustomerGateway*",
    "ec2:*ClassicLink*",
    "elasticloadbalancing:*",
  ]

  boundary_denied_network_infra_actions = [
    "ec2:CreateVpc",
    "ec2:DeleteVpc",
    "ec2:ModifyVpc*",
    "ec2:CreateDefaultVpc",
    "ec2:AssociateVpcCidrBlock",
    "ec2:DisassociateVpcCidrBlock",
    "ec2:CreateSubnet",
    "ec2:DeleteSubnet",
    "ec2:ModifySubnetAttribute",
    "ec2:CreateDefaultSubnet",
    "ec2:AssociateSubnetCidrBlock",
    "ec2:DisassociateSubnetCidrBlock",
    "ec2:CreateRoute",
    "ec2:DeleteRoute",
    "ec2:ReplaceRoute",
    "ec2:CreateRouteTable",
    "ec2:DeleteRouteTable",
    "ec2:AssociateRouteTable",
    "ec2:DisassociateRouteTable",
    "ec2:ReplaceRouteTableAssociation",
    "ec2:EnableVgwRoutePropagation",
    "ec2:DisableVgwRoutePropagation",
    "ec2:Create*Gateway*",
    "ec2:Delete*Gateway*",
    "ec2:Attach*Gateway*",
    "ec2:Detach*Gateway*",
    "ec2:Modify*Gateway*",
    "ec2:CreateVpcEndpoint*",
    "ec2:DeleteVpcEndpoint*",
    "ec2:ModifyVpcEndpoint*",
    "ec2:AcceptVpcEndpointConnections",
    "ec2:RejectVpcEndpointConnections",
    "ec2:CreateVpcPeeringConnection",
    "ec2:DeleteVpcPeeringConnection",
    "ec2:AcceptVpcPeeringConnection",
    "ec2:RejectVpcPeeringConnection",
    "ec2:ModifyVpcPeeringConnectionOptions",
    "ec2:*Dhcp*",
    "ec2:*NetworkAcl*",
    "ec2:*Vpn*",
    "ec2:*CustomerGateway*",
    "ec2:*ClassicLink*",
    "ec2:*Address*",
    "ec2:*PlacementGroup*",
    "elasticloadbalancing:*",
    "route53:*VPC*",
    "route53:*HostedZone*",
  ]

  boundary_no_role_assumption = {
    Sid         = "NoRoleAssumption"
    Effect      = "Deny"
    Action      = "sts:AssumeRole"
    NotResource = local.boundary_assumable_role_arns
    Condition   = local.boundary_principal_account_condition
  }
  boundary_no_org = {
    Sid       = "NoOrg"
    Effect    = "Deny"
    Action    = "organizations:*"
    Resource  = "*"
    Condition = local.boundary_principal_account_condition
  }
  boundary_no_iam_write = {
    Sid       = "NoIAMWrite"
    Effect    = "Deny"
    Action    = local.boundary_denied_iam_write_actions
    Resource  = "*"
    Condition = local.boundary_principal_account_condition
  }
  boundary_allow_all = {
    Sid       = "AllowAll"
    Effect    = "Allow"
    Action    = "*"
    Resource  = "*"
    Condition = local.boundary_principal_account_condition
  }

  ecs_execution_boundary_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenySTSExceptTagSession"
        Effect    = "Deny"
        Action    = concat(["sts:AssumeRole"], local.boundary_denied_sts_actions)
        Resource  = "*"
        Condition = local.boundary_principal_account_condition
      },
      local.boundary_no_org,
      {
        Sid       = "NoIAM"
        Effect    = "Deny"
        Action    = "iam:*"
        Resource  = "*"
        Condition = local.boundary_principal_account_condition
      },
      {
        Sid       = "NoNetworkInfraWrite"
        Effect    = "Deny"
        Action    = local.boundary_denied_network_infra_actions
        Resource  = "*"
        Condition = local.boundary_principal_account_condition
      },
      {
        Sid       = "NoEC2"
        Effect    = "Deny"
        Action    = "ec2:*"
        Resource  = "*"
        Condition = local.boundary_principal_account_condition
      },
      local.boundary_allow_all,
    ]
  }

  ecs_task_boundary_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenySTSExceptAssumeRole"
        Effect    = "Deny"
        Action    = local.boundary_denied_sts_actions
        Resource  = "*"
        Condition = local.boundary_principal_account_condition
      },
      local.boundary_no_org,
      {
        Sid       = "NoNet"
        Effect    = "Deny"
        Action    = local.boundary_denied_runner_network_actions
        Resource  = "*"
        Condition = local.boundary_principal_account_condition
      },
      local.boundary_no_iam_write,
      local.boundary_allow_all,
    ]
  }

  proxy_boundary_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "ec2:DescribeInstances"
        Resource  = "*"
        Condition = local.boundary_principal_account_condition
      },
      {
        Sid       = "AllowS3ReadAccessForGitpod"
        Effect    = "Allow"
        Action    = "s3:GetObject"
        Resource  = "arn:aws:s3:::gitpod-*/*"
        Condition = local.boundary_principal_account_condition
      },
    ]
  }

  adot_boundary_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:ListTasks",
          "ecs:ListServices",
          "ecs:DescribeTasks",
          "ecs:DescribeTaskDefinition",
          "ecs:DescribeServices",
          "ecs:DescribeContainerInstances",
        ]
        Resource  = "*"
        Condition = local.boundary_principal_account_condition
      },
      {
        Sid       = "AllowS3ReadAccessForGitpod"
        Effect    = "Allow"
        Action    = "s3:GetObject"
        Resource  = "arn:aws:s3:::gitpod-*/*"
        Condition = local.boundary_principal_account_condition
      },
      {
        Effect    = "Allow"
        Action    = ["s3:PutObject", "s3:GetBucketLocation"]
        Resource  = "*"
        Condition = local.boundary_principal_account_condition
      },
    ]
  }

  environment_boundary_policy = {
    Version = "2012-10-17"
    Statement = [
      local.boundary_no_role_assumption,
      local.boundary_no_org,
      local.boundary_no_iam_write,
      {
        Sid       = "NoNetworkInfraWrite"
        Effect    = "Deny"
        Action    = local.boundary_denied_network_infra_actions
        Resource  = "*"
        Condition = local.boundary_principal_account_condition
      },
      {
        Sid       = "NoEC2Danger"
        Effect    = "Deny"
        Action    = ["ec2:*Reserved*", "ec2:*Purchase*", "ec2:*Host*"]
        Resource  = "*"
        Condition = local.boundary_principal_account_condition
      },
      local.boundary_allow_all,
    ]
  }

  s3_access_boundary_policy = {
    Version = "2012-10-17"
    Statement = [
      local.boundary_no_role_assumption,
      local.boundary_no_org,
      local.boundary_no_iam_write,
      {
        Sid       = "NoEC2"
        Effect    = "Deny"
        Action    = "ec2:*"
        Resource  = "*"
        Condition = local.boundary_principal_account_condition
      },
      {
        Sid       = "NoLogs"
        Effect    = "Deny"
        Action    = "logs:*"
        Resource  = "*"
        Condition = local.boundary_principal_account_condition
      },
      local.boundary_allow_all,
    ]
  }

  devcontainer_cache_boundary_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenySTSExceptTagSession"
        Effect    = "Deny"
        Action    = concat(["sts:AssumeRole"], local.boundary_denied_sts_actions)
        Resource  = "*"
        Condition = local.boundary_principal_account_condition
      },
      local.boundary_no_org,
      {
        Sid       = "NoIAM"
        Effect    = "Deny"
        Action    = "iam:*"
        Resource  = "*"
        Condition = local.boundary_principal_account_condition
      },
      {
        Sid       = "NoNetworkInfraWrite"
        Effect    = "Deny"
        Action    = local.boundary_denied_network_infra_actions
        Resource  = "*"
        Condition = local.boundary_principal_account_condition
      },
      {
        Sid       = "NoEC2"
        Effect    = "Deny"
        Action    = "ec2:*"
        Resource  = "*"
        Condition = local.boundary_principal_account_condition
      },
      {
        Sid       = "NoLogs"
        Effect    = "Deny"
        Action    = "logs:*"
        Resource  = "*"
        Condition = local.boundary_principal_account_condition
      },
      {
        Sid       = "NoS3"
        Effect    = "Deny"
        Action    = "s3:*"
        Resource  = "*"
        Condition = local.boundary_principal_account_condition
      },
      local.boundary_allow_all,
    ]
  }
}

resource "aws_iam_policy" "ecs_execution_boundary" {
  name_prefix = "${local.iam_role_name_prefix}-ecs-exec-boundary-"
  description = "Permission boundary for the Ona runner ECS execution role"
  policy      = jsonencode(local.ecs_execution_boundary_policy)
  tags        = local.common_tags
}

resource "aws_iam_policy" "ecs_task_boundary" {
  name_prefix = "${local.iam_role_name_prefix}-ecs-task-boundary-"
  description = "Permission boundary for the Ona runner ECS task role"
  policy      = jsonencode(local.ecs_task_boundary_policy)
  tags        = local.common_tags
}

resource "aws_iam_policy" "proxy_boundary" {
  name_prefix = "${local.iam_role_name_prefix}-proxy-boundary-"
  description = "Permission boundary for the Ona runner proxy role"
  policy      = jsonencode(local.proxy_boundary_policy)
  tags        = local.common_tags
}

resource "aws_iam_policy" "adot_boundary" {
  name_prefix = "${local.iam_role_name_prefix}-adot-boundary-"
  description = "Permission boundary for the Ona runner ADOT role"
  policy      = jsonencode(local.adot_boundary_policy)
  tags        = local.common_tags
}

resource "aws_iam_policy" "environment_boundary" {
  name_prefix = "${local.iam_role_name_prefix}-environment-boundary-"
  description = "Permission boundary for Ona environment instances"
  policy      = jsonencode(local.environment_boundary_policy)
  tags        = local.common_tags
}

resource "aws_iam_policy" "s3_access_boundary" {
  name_prefix = "${local.iam_role_name_prefix}-s3-boundary-"
  description = "Permission boundary for the Ona runner S3 access role"
  policy      = jsonencode(local.s3_access_boundary_policy)
  tags        = local.common_tags
}

resource "aws_iam_policy" "devcontainer_cache_boundary" {
  name_prefix = "${local.iam_role_name_prefix}-ecr-boundary-"
  description = "Permission boundary for the Ona devcontainer cache registry role"
  policy      = jsonencode(local.devcontainer_cache_boundary_policy)
  tags        = local.common_tags
}
