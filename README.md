# ☁️ Laboratório de Monitoramento e Auditoria AWS com Terraform

Este projeto automatiza a criação de um ambiente de laboratório na AWS focado em **Monitoramento (CloudWatch)** e **Auditoria (CloudTrail)** utilizando **Terraform**.

O objetivo é provisionar uma infraestrutura segura e observável, onde uma instância EC2 é monitorada por alarmes de CPU e todas as ações da conta são registradas em logs criptografados.

---

## 🏗️ Arquitetura e Recursos

O código Terraform (`main.tf`) provisiona os seguintes recursos na região `us-east-1` (N. Virginia):

1.  **Compute (EC2):**
    * Instância `t2.micro` (Free Tier) usando a AMI mais recente do **Amazon Linux 2023**.
    * **Security Group:** Configurado para permitir acesso SSH (porta 22).

2.  **Monitoramento (CloudWatch & SNS):**
    * **Alarme de CPU:** Dispara quando a utilização da CPU ultrapassa **70%**.
    * **SNS Topic:** Envia uma notificação por e-mail quando o alarme é acionado.

3.  **Auditoria e Segurança (CloudTrail, S3 & KMS):**
    * **CloudTrail:** Trilha de auditoria multi-região ativada.
    * **Bucket S3:** Armazenamento seguro dos logs de auditoria.
    * **KMS Key:** Chave gerenciada pelo cliente (CMK) para criptografar os logs no S3.
    * **S3 Bucket Policy:** Políticas rigorosas para permitir apenas a gravação pelo serviço CloudTrail.

---

## 🛠️ Pré-requisitos

Para executar este projeto, você precisará ter instalado e configurado em sua máquina:

* [Terraform](https://developer.hashicorp.com/terraform/downloads) (v1.0+)
* [AWS CLI](https://aws.amazon.com/cli/) (Configurado com `aws configure`)
* Uma conta AWS ativa.
* Um par de chaves SSH (Key Pair) criado no console da AWS na região `us-east-1`.

---

## 🚀 Como Executar

### 1. Clonar o Repositório

```bash
git clone [https://github.com/SEU-USUARIO/aws-cloudwatch-cloudtrail-lab.git](https://github.com/SEU-USUARIO/aws-cloudwatch-cloudtrail-lab.git)
cd aws-cloudwatch-cloudtrail-lab
```

Inicializar o Terraform
Baixe os provedores necessários (AWS, Random, Null):

```Bash

terraform init
```
3. Planejar e Aplicar a Infraestrutura
Execute o comando abaixo. Você precisará fornecer duas variáveis essenciais:

sns_email: O e-mail que receberá os alertas.

key_name: O nome do par de chaves (Key Pair) que você criou na AWS.

```Bash

terraform apply \
  -var="sns_email=seu@email.com" \
  -var="key_name=nome-da-sua-chave"
```
Digite yes quando solicitado para confirmar a criação.

🧪 Validando o Laboratório
Após o terraform apply ser concluído com sucesso:

Confirme o E-mail:

Vá para a caixa de entrada do e-mail fornecido.

Clique no link de confirmação da AWS ("AWS Notification - Subscription Confirmation").

Acesse a Instância:

Use o IP público fornecido no output do Terraform (instance_public_ip) e sua chave privada:

```Bash

ssh -i sua-chave.pem ec2-user@<IP_PUBLICO>
```
Gere Carga de CPU (Teste de Stress):

Dentro da instância, instale e execute o stress:

```Bash

sudo yum update -y
sudo amazon-linux-extras install epel -y  # Ou: sudo dnf install stress -y (no AL2023)
sudo yum install stress -y
stress --cpu 8 --timeout 600
```
Observe o Monitoramento:

Aguarde alguns minutos e verifique o console do CloudWatch. O alarme mudará para o estado ALARM e você receberá um e-mail.

Verifique o console do S3 (no bucket criado) para ver os logs de auditoria gerados pelo CloudTrail.

🧹 Limpeza (Destruição)
Para evitar cobranças indesejadas, destrua a infraestrutura quando terminar o laboratório.

Nota: O bucket S3 está configurado com force_destroy = true, então ele será apagado mesmo contendo logs.

```Bash

terraform destroy \
  -var="sns_email=seu@email.com" \
  -var="key_name=nome-da-sua-chave"
```
Digite yes para confirmar a exclusão de todos os recursos.

🔒 Segurança
Este projeto utiliza .gitignore para excluir arquivos de estado sensíveis (*.tfstate) e arquivos de variáveis (*.tfvars).

A chave KMS garante que os logs de auditoria sejam criptografados em repouso.

Nunca comite sua chave privada (.pem) ou credenciais AWS no repositório.


