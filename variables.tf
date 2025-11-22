variable "region" {
  description = "Região da AWS para provisionamento"
  default     = "us-east-1"
}

variable "instance_type" {
  description = "Tipo da instância EC2 (t2.micro é Free Tier)"
  default     = "t2.micro" 
}

variable "sns_email" {
  description = "Seu e-mail para receber notificações do Alarme CloudWatch."
  type        = string
  sensitive   = true 
}

variable "key_name" {
  description = "Nome do par de chaves EC2 existente para acesso SSH."
  type        = string
}

variable "security_group_name" {
  description = "Nome do Security Group a ser criado."
  default     = "SG-Teste-CloudWatch-Lab"
}
