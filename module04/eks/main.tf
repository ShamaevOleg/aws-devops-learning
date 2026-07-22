data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "vpc_for_eks" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "AWS Virtual Private Cloud for EKS"
  }
}

resource "aws_subnet" "subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.vpc_for_eks.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = "true"

  tags = {
    Name                     = "subnet-${data.aws_availability_zones.available.names[count.index]}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_internet_gateway" "gw_eks" {
  vpc_id = aws_vpc.vpc_for_eks.id

  tags = {
    Name = "AWS IGW for EKS"
  }
}

resource "aws_route_table" "route_eks" {
  vpc_id = aws_vpc.vpc_for_eks.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw_eks.id
  }

  tags = {
    Name = "AWS ROUTE TABLE FOR EKS"
  }
}

resource "aws_route_table_association" "rt_association_eks" {
  count          = 2
  subnet_id      = aws_subnet.subnet[count.index].id
  route_table_id = aws_route_table.route_eks.id
}

resource "aws_iam_role" "eks_cluster_role" {
  name               = "eks_cluster_role"
  assume_role_policy = data.aws_iam_policy_document.eks_trust.json
}

resource "aws_iam_role" "eks_node_role" {
  name               = "eks_node_role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json

}

data "aws_iam_policy_document" "eks_trust" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_role_attachment" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_role_attachment" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])
  role       = aws_iam_role.eks_node_role.name
  policy_arn = each.value
}
