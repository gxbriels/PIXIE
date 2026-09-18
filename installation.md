# Tutorial Prático: Instalação e Visualização Prévia do Pixie

Este guia foi elaborado para qualquer pessoa conseguir instalar e testar o **Pixie** em um ambiente Linux (máquina virtual ou servidor local), mesmo sem experiência prévia com Kubernetes ou ferramentas de observabilidade.

---

## 1. O que é o Pixie e do que precisamos?

- **Pixie**: Uma ferramenta de monitoramento e observabilidade em tempo real para aplicações em nuvem que usam Kubernetes. Ela coleta métricas de rede, requisições HTTP, uso de CPU e banco de dados automaticamente.
- **Kubernetes (k8s)**: Um sistema para orquestrar e gerenciar aplicações em contêineres.
- **Minikube**: Um programa que simula um cluster Kubernetes completo diretamente no seu computador para testes e estudos.
- **Docker**: A base que permite empacotar e rodar programas isolados (contêineres).

---

## Passo 1: Atualizar o Sistema e Instalar Dependências Básicas

Antes de começar, garantimos que o sistema operacional esteja atualizado e com as ferramentas essenciais para baixar arquivos e gerenciar conexões seguras.

```bash
sudo apt update && sudo apt upgrade -y
```
> **Para que serve:** O `apt update` sincroniza a lista de programas disponíveis mais recentes, e o `apt upgrade` atualiza os pacotes já instalados na máquina para evitar erros de compatibilidade.

```bash
sudo apt install -y curl wget apt-transport-https ca-certificates software-properties-common
```
> **Para que serve:** Instala ferramentas utilitárias (`curl` e `wget` para baixar arquivos pela internet e certificados de segurança para download seguro via HTTPS).

---

## Passo 2: Instalar e Configurar o Docker

O Minikube usará o Docker como "motor" para rodar o Kubernetes.

```bash
sudo apt install -y docker.io
```
> **Para que serve:** Faz a instalação do serviço Docker no sistema.

```bash
sudo usermod -aG docker $USER
```
> **Para que serve:** Adiciona o seu usuário atual (`$USER`) ao grupo de permissões do Docker, permitindo que você execute comandos do Docker sem precisar digitar `sudo` toda vez.

```bash
su - $USER
```
> **Para que serve:** Atualiza a sessão do terminal para que a permissão de grupo adicionada no comando anterior entre em vigor imediatamente.

```bash
docker ps
```
> **Para que serve:** Testa se o Docker está funcionando corretamente listando os contêineres ativos (se não der erro de permissão, está tudo pronto).

---

## Passo 3: Instalar o `kubectl` (Gerenciador do Kubernetes)

O `kubectl` é a ferramenta de linha de comando oficial para interagir e enviar ordens ao Kubernetes.

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
```
> **Para que serve:** Baixa a versão estável mais recente do executável do `kubectl`.

```bash
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```
> **Para que serve:** Move o arquivo baixado para a pasta `/usr/local/bin` e dá permissão de execução, permitindo que o comando `kubectl` seja usado de qualquer lugar do terminal.

```bash
kubectl version --client
```
> **Para que serve:** Verifica se a ferramenta foi instalada com sucesso e exibe a versão atual.

---

## Passo 4: Instalar e Iniciar o Minikube

O Minikube fornecerá o cluster Kubernetes local onde o Pixie será implantado.

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
```
> **Para que serve:** Faz o download do instalador do Minikube para sistemas Linux 64 bits.

```bash
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```
> **Para que serve:** Instala o Minikube no diretório global de comandos do sistema com as permissões adequadas.

```bash
minikube start --driver=docker --cpus=2 --memory=4096
```
> **Para que serve:** Inicializa o cluster Kubernetes local utilizando o Docker como motor e alocando **2 núcleos de CPU** e **4 GB de memória RAM** (requisitos mínimos recomendados para o Pixie rodar confortavelmente).

---

## Passo 5: Instalar e Configurar o CLI do Pixie (`px`)

Para enviar o Pixie para dentro do Kubernetes e visualizar os dados, utilizamos a ferramenta de linha de comando chamada `px`.

> *Dica de instalação rápida do CLI oficial do Pixie:*
> ```bash
> bash -c "$(curl -fsSL https://withpixie.ai/install.sh)"
> ```
> *(O executável padrão costuma ser salvo em `~/bin/px`)*.

Caso o executável tenha sido baixado em `~/bin/px`:

```bash
mv ~/bin/px ~/bin/pixie
```
> **Para que serve:** Renomeia o binário `px` para `pixie` (caso prefira chamar pelo nome completo).

```bash
~/bin/pixie version
```
> **Para que serve:** Exibe a versão instalada do CLI do Pixie, confirmando que o arquivo está funcionando.

```bash
~/bin/pixie auth login --manual
```
> **Para que serve:** Inicia o processo de autenticação na plataforma do Pixie Cloud via navegador ou código manual, vinculando sua instalação à sua conta.

---

## Passo 6: Implantar (Deploy) o Pixie no Cluster

Agora que o Minikube está rodando e a ferramenta Pixie está autenticada, enviamos o agente do Pixie para dentro do Kubernetes:

```bash
~/bin/pixie deploy
```
> **Para que serve:** Instala automaticamente os componentes do Pixie (coletores e agentes eBPF) dentro do cluster Kubernetes em execução.

---

## Passo 7: Acompanhar e Validar o Funcionamento

Para saber se o Pixie já está rodando e pronto para monitorar:

```bash
minikube kubectl -- get pods -n pl -w
```
> **Para que serve:**
> - `get pods -n pl`: Lista os módulos (pods) em execução no namespace do Pixie (`pl`).
> - `-w` (*watch*): Mantém o terminal aberto atualizando em tempo real até que todos os itens estejam com status `Running` (em execução).

---

## Passo 8: Visualização Prévia dos Dados

Após todos os pods estarem ativos:

1. Acesse o painel web no endereço indicado durante o comando de login: **[https://work.withpixie.ai](https://work.withpixie.ai)**.
2. No painel, selecione o seu cluster do Minikube no menu superior.
3. Você terá acesso aos scripts integrados do Pixie para inspecionar requisições HTTP, uso de tráfego de rede e consumo de recursos sem precisar configurar nada a mais!
