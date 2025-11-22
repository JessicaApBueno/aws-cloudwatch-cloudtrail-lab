# Configura o provedor AWS
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Fonte de dados para obter o ID da conta AWS
data "aws_caller_identity" "current" {}

# Data Source para buscar o AMI ID mais recente do Amazon Linux 2 HVM via SSM
data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

# --- Recursos de Rede e EC2 ---

# Cria um Security Group para permitir SSH
resource "aws_security_group" "lab_sg" {
  name        = var.security_group_name
  description = "Allow SSH inbound traffic"
  
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = var.security_group_name
  }
}

# Instância EC2 de Teste (t2.micro)
resource "aws_instance" "test_instance" {
  ami                    = data.aws_ssm_parameter.ami.value
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.lab_sg.id]
  associate_public_ip_address = true
  
  tags = {
    Name = "Instancia-Teste-CloudWatch"
  }
}

# --- Recursos de Monitoramento (CloudWatch e SNS) ---

# Tópico SNS para notificação por e-mail
resource "aws_sns_topic" "cpu_alarm_topic" {
  name = "AlarmeCPU-Topic"
}

# Inscrição do seu e-mail no Tópico SNS 
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.cpu_alarm_topic.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

# Alarme CloudWatch (Monitoramento de CPU > 70%)
resource "aws_cloudwatch_metric_alarm" "cpu_utilization_alarm" {
  alarm_name                = "AlarmeCPU-Instancia-${var.key_name}"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "1"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "300" # 5 minutos
  statistic                 = "Average"
  threshold                 = "70" # 70%
  alarm_description         = "Alerta quando a utilização da CPU excede 70%."
  alarm_actions             = [aws_sns_topic.cpu_alarm_topic.arn]

  dimensions = {
    InstanceId = aws_instance.test_instance.id
  }
}

# --- Recursos de Auditoria (CloudTrail, S3 e KMS) ---

# Usar um recurso 'random_id' para garantir que o nome do bucket seja único
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# 1. Bucket S3 (SEM BLOCO POLICY)
resource "aws_s3_bucket" "cloudtrail_log_bucket" {
  bucket = "cloudtrail-logs-auditoria-${random_id.bucket_suffix.hex}" 

  lifecycle {
    prevent_destroy = true 
  }
}

# 2. POLÍTICA DO S3 SEPARADA
resource "aws_s3_bucket_policy" "cloudtrail_bucket_policy" {
  bucket = aws_s3_bucket.cloudtrail_log_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail_log_bucket.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail_log_bucket.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}


# Chave KMS para criptografia dos logs
resource "aws_kms_key" "cloudtrail_kms_key" {
  description             = "Chave KMS para logs do CloudTrail"
  deletion_window_in_days = 7
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid = "Allow CloudTrail to encrypt logs"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          # CORREÇÃO CRÍTICA: Usar 'StringLike' para SourceArn (pois tem asterisco)
          # e 'StringEquals' para SourceAccount.
          StringLike = {
            "aws:SourceArn" = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/*"
          }
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_kms_alias" "cloudtrail_kms_alias" {
  name          = "alias/CloudTrailKey-auditoria-${var.key_name}"
  target_key_id = aws_kms_key.cloudtrail_kms_key.id
}

# RECURSO NULL_RESOURCE: Pausa para propagação
resource "null_resource" "kms_propagation_wait" {
  depends_on = [
    aws_kms_key.cloudtrail_kms_key
  ]

  provisioner "local-exec" {
    command = "sleep 10" # Reduzi para 10s pois a correção da política deve ser imediata
  }
}


# Trilha CloudTrail (Auditoria)
resource "aws_cloudtrail" "audit_trail" {
  name                          = "trilha-auditoria-${var.key_name}"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_log_bucket.bucket
  include_global_service_events = true
  is_multi_region_trail         = true 
  enable_log_file_validation    = true
  enable_logging                = true
  kms_key_id                    = aws_kms_key.cloudtrail_kms_key.arn

  # Dependências
  depends_on = [
    aws_s3_bucket_policy.cloudtrail_bucket_policy,
    null_resource.kms_propagation_wait
  ]

  # Configuração de eventos de gerenciamento
  event_selector {
    read_write_type             = "All"
    include_management_events   = true
  }
}

# --- Saídas Úteis (Outputs) ---

output "instance_id" {
  description = "ID da Instância EC2 (Anote este ID)"
  value       = aws_instance.test_instance.id
}

output "instance_public_ip" {
  description = "IP Público da Instância EC2 (Use para SSH)"
  value       = aws_instance.test_instance.public_ip
}

# Marcar output como 'sensitive'
output "sns_confirmation_needed" {
  description = "PASSO CRUCIAL: Verifique e confirme a inscrição no e-mail fornecido."
  value       = "Confirmação pendente para ${var.sns_email}. Verifique a caixa de entrada para o e-mail AWS SNS."
  sensitive   = true 
}

output "cloudtrail_s3_bucket_name" {
  description = "Nome do Bucket S3 onde os logs do CloudTrail serão armazenados (Necessário para a limpeza)"
  value       = aws_s3_bucket.cloudtrail_log_bucket.bucket
}
