# Guia de Implantação: Observabilidade eBPF com Pixie
**Ambiente:** Ubuntu Linux (Nativo, VM ou WSL2) + Minikube (Docker)
**Disciplina:** Laboratórios de Pesquisa I e II - Sistemas de Informação
**Foco:** Programabilidade com eBPF (Observabilidade, Tracing e Desempenho)

---

## 1. Preparação da Infraestrutura Base

O sistema operacional hospedeiro precisa estar atualizado e possuir os cabeçalhos do kernel correspondentes à versão em execução. Isso é obrigatório para permitir que o compilador JIT crie os programas eBPF de forma segura em nível de kernel (Kernel Space).

```bash
# Atualiza os índices e os pacotes do Ubuntu
sudo apt update && sudo apt upgrade -y

# Instala os cabeçalhos do Kernel exatos da máquina atual (Obrigatório para o eBPF)
sudo apt install -y linux-headers-$(uname -r)

    🔴 Possível Erro: Falha por falta de espaço em disco na partição raiz (/)
    Sintoma: No space left on device ou 0 bytes free durante a instalação.
    Solução (Troubleshooting de Disco):
    Bash

    # 1. Remove pacotes e dependências órfãs do sistema
    sudo apt autoremove -y
    # 2. Limpa o cache de downloads do apt
    sudo apt clean
    # 3. Remove logs antigos do sistema (mantém apenas as últimas 2 semanas)
    sudo journalctl --vacuum-time=2w
    # 4. Remove imagens e contêineres ociosos do Docker
    docker system prune -a
    # 5. Verifique o espaço liberado
    df -h /

2. Configuração do Orquestrador (Minikube + Docker)

O Pixie roda sobre o Kubernetes. Para um ambiente de laboratório (sandbox), utilizaremos o Minikube orquestrando contêineres Docker.
Bash

# Instala o Docker
sudo apt install -y docker.io

# Inicia o daemon do Docker no systemd
sudo systemctl enable --now docker

# Adiciona o usuário atual ao grupo docker para evitar o uso de sudo
sudo usermod -aG docker $USER

    Nota: Após rodar o comando usermod, é necessário fechar e abrir o terminal novamente, ou executar o comando newgrp docker para aplicar as permissões.

Bash

# Baixa e instala o Minikube
curl -LO [https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64](https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64)
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Inicia o cluster local alocando recursos adequados para processar telemetria (Mínimo 4GB)
minikube start --driver=docker --memory=4096 --cpus=4

3. Instalação da CLI do Pixie (px)

O utilitário px é a ferramenta de linha de comando responsável por interagir com os sensores e implantar a infraestrutura.
Bash

# Baixa e executa o script oficial de instalação
bash -c "$(curl -fsSL [https://withpixie.ai/install.sh](https://withpixie.ai/install.sh))"

    🔴 Possível Erro: Comando não encontrado
    Sintoma: bash: px: command not found
    Causa: O binário foi instalado, mas a pasta não consta na variável de ambiente do sistema.
    Solução:
    Bash

    # Adiciona o diretório padrão do Pixie ao PATH do Ubuntu (~/.bashrc)
    echo 'export PATH="$PATH:$HOME/.pixie/bin"' >> ~/.bashrc
    source ~/.bashrc

    (Nota: O script de instalação informará o caminho exato caso seja diferente).

4. Autenticação na Plataforma
Bash

px auth login

    🔴 Possíveis Erros na Autenticação:

    Erro A: O terminal abre um navegador incorreto ou trava na linha de comando.
    Solução (Forçar o Firefox como padrão no Ubuntu):
    Bash

    echo 'export BROWSER="firefox"' >> ~/.bashrc
    source ~/.bashrc
    xdg-settings set default-web-browser firefox.desktop

    Erro B: Erro de sessão "Oops!, something went wrong" (Falha de cookies/estado).
    Solução (Autenticação Manual / Out-of-Band):
    Bash

    px auth login --manual

    Copie a URL gerada no terminal, abra uma aba Anônima/Privada no navegador, faça o login e cole o token JWT resultante de volta no terminal.

5. Injeção do eBPF (Deployment)

Antes de implantar, a ferramenta Pixie exige comunicação direta com o orquestrador através do utilitário nativo do Kubernetes (kubectl).

    🔴 Possível Erro: Falha no Pre-Check do Deploy
    Sintoma: ERR: exec: "kubectl": executable file not found in $PATH
    Causa: O Ubuntu não possui o kubectl instalado nativamente por padrão.
    Solução:
    Bash

    # Instala o kubectl através do gerenciador de pacotes Snap (padrão no Ubuntu)
    sudo snap install kubectl --classic

Iniciando o Deploy:
Bash

px deploy

    Nota: O instalador fará um Pre-Check. Como estamos rodando em Minikube, ele pode alertar que o tipo de cluster não é oficial para produção corporativa. Pressione y para confirmar e forçar a instalação no ambiente de laboratório.

6. Validação e Geração de Carga (Teste Prático)

Verifique se os sensores de nível de núcleo (Viziers) foram acoplados com sucesso e se encontraram os cabeçalhos do Ubuntu:
Bash

# Verifica o status geral e a integridade da compilação JIT
px get viziers

# Inspeciona os processos rodando no namespace do Pixie
minikube kubectl -- get pods -n pl

Para validar a ferramenta de observabilidade e os relatórios de Tracing, precisamos de uma aplicação alvo gerando tráfego HTTP e consumo de CPU:
Bash

# Implanta a aplicação de demonstração baseada em microsserviços (Sock Shop)
px demo deploy px-sock-shop

    🔴 Possível Erro na Leitura de Métricas PxL
    Sintoma: Compiler error: Table 'http_events' not found ao rodar consultas como px/service_stats.
    Causa: A tabela no Pixie só é criada dinamicamente na memória quando o eBPF captura o primeiro pacote. Se a rede do cluster estiver silenciosa, a tabela não existe.
    Solução (Simular tráfego de clientes reais):
    Bash

    # Crie um túnel do Ubuntu para a loja rodando dentro do cluster
    minikube kubectl -- port-forward svc/front-end 8080:80 -n px-sock-shop

    Mantenha o terminal aberto. Acesse http://localhost:8080 no seu navegador, navegue pelos produtos e adicione itens ao carrinho. Isso gerará o tráfego HTTP interno necessário para o eBPF popular as tabelas, permitindo o funcionamento dos gráficos na plataforma web.