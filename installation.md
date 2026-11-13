# Tutorial Prático: Instalação e Visualização Prévia do Pixie

Este guia foi elaborado para qualquer pessoa conseguir instalar e testar o **Pixie** em um ambiente Linux (máquina virtual ou servidor local), mesmo sem experiência prévia com Kubernetes ou ferramentas de observabilidade.

---

## O que é o Pixie e do que precisamos?

- **Pixie**: Uma ferramenta de monitoramento e observabilidade em tempo real para aplicações em nuvem que usam Kubernetes. Ela coleta métricas de rede, requisições HTTP, uso de CPU e banco de dados automaticamente.
- **Kubernetes (k8s)**: Um sistema para orquestrar e gerenciar aplicações em contêineres.
- **Minikube**: Um programa que simula um cluster Kubernetes completo diretamente no seu computador para testes e estudos.
- **Docker**: A base que permite empacotar e rodar programas isolados (contêineres).

Este documento também detalha o procedimento completo e padronizado para configurar o laboratório de observabilidade de redes utilizando **Minikube com driver KVM2**, **CNI Flannel**, **Pixie eBPF** e a aplicação de microsserviços **Google Online Boutique**.

---

## 1. Por que utilizar o Driver KVM2 e a CNI Flannel?

1. **Superação das limitações do Driver Docker:** Quando o Minikube roda sobre o driver `docker`, o nó do Kubernetes opera dentro de um contêiner compartilhando o kernel do host. Isso impede o agente **PEM (*Pixie Edge Module*)** de acessar corretamente os cabeçalhos do kernel (`KERNEL HEADERS INSTALLED: false`), quebrando a compilação *Just-In-Time* das sondas eBPF de Camada 7 (tabelas `http_events` e script `px/http_data` ficam vazios).
2. **Isolamento via QEMU/KVM (`kvm2`):** Cria uma máquina virtual dedicada com kernel próprio dotado de suporte a **BTF/CO-RE**, permitindo rastreamento nativo de protocolos L4 e L7 (HTTP, gRPC e DNS).
3. **CNI Flannel (`--cni=flannel`):** Obrigatória em versões modernas do Minikube para que o Pixie consiga correlacionar os endereços IP dos pods com os nomes dos serviços Kubernetes e desenhar os grafos de dependência.

---

## Passo 1: Habilitar Virtualização Aninhada (Apenas para Usuários de VirtualBox)

> **Nota:** Se você estiver executando o Linux nativamente na máquina física (*bare-metal*), pule diretamente para o **Passo 2**.

Caso o seu ambiente Linux seja uma máquina virtual rodando dentro do **Oracle VirtualBox**, é obrigatório repassar as instruções de virtualização do processador físico (`VT-x` ou `AMD-V`) para a VM desligada.

No terminal do sistema hospedeiro (**Windows PowerShell como Administrador**):

```powershell
cd "C:\Program Files\Oracle\VirtualBox"
VBoxManage modifyvm "Nome-Exato-Da-Sua-VM" --nested-hw-virt on
```

**Retorno esperado:**
*(O comando executa silenciosamente e retorna ao prompt sem mensagens de erro, ativando a caixa "Habilitar VT-x/AMD-V aninhado" nas configurações de Processador da VM).*

---

## Passo 2: Preparar o Sistema e Instalar o Hipervisor KVM/Libvirt

Escolha abaixo a subseção correspondente à sua distribuição Linux (**2A para Ubuntu/Debian** ou **2B para Arch Linux**).

### 2A. Ambiente Ubuntu / Debian

1. Atualize os pacotes e instale os cabeçalhos do kernel e utilitários básicos:
   ```bash
   sudo apt update && sudo apt upgrade -y
   sudo apt install -y linux-headers-$(uname -r) build-essential dkms curl wget apt-transport-https ca-certificates software-properties-common
   ```
   **Retorno esperado:**
   ```text
   Reading package lists... Done
   Building dependency tree... Done
   ...
   Setting up linux-headers-6.x.x-xx-generic ...
   ```

2. Instale a pilha de virtualização QEMU/KVM e Libvirt:
   ```bash
   sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst cpu-checker
   ```
   **Retorno esperado:**
   ```text
   Setting up libvirt-daemon-system ...
   Created symlink /etc/systemd/system/multi-user.target.wants/libvirtd.service ...
   ```

3. Verifique se a aceleração por hardware KVM está ativa:
   ```bash
   kvm-ok
   ```
   **Retorno esperado:**
   ```text
   INFO: /dev/kvm exists
   KVM acceleration can be used
   ```

4. Ative o serviço `libvirtd` e adicione seu usuário aos grupos `libvirt` e `kvm`:
   ```bash
   sudo systemctl enable --now libvirtd
   sudo usermod -aG libvirt,kvm $USER
   newgrp libvirt
   ```
   **Retorno esperado:**
   *(O comando atualiza a sessão do shell corrente sem exibir erros).*

---

### 2B. Ambiente Arch Linux (Nativo)

1. Verifique o suporte de virtualização do processador e os módulos do kernel carregados:
   ```zsh
   LC_ALL=C lscpu | grep Virtualization
   lsmod | grep kvm
   ```
   **Retorno esperado:**
   ```text
   Virtualization:                  VT-x
   kvm_intel             524288  0
   kvm                  1499136  1 kvm_intel
   irqbypass              16384  1 kvm
   ```

2. Instale os pacotes oficiais do QEMU, Libvirt e gerenciadores de rede (sobrescrevendo eventuais conflitos de bibliotecas Python locais):
   ```zsh
   sudo pacman -S --needed --overwrite "/usr/lib/python3.*/*,/usr/bin/normalizer,/usr/bin/idna" qemu-desktop libvirt virt-manager dnsmasq dmidecode iptables
   ```
   **Retorno esperado:**
   ```text
   (80/80) verificando integridade do pacote          [########################################] 100%
   (80/80) instalando libvirt                         [########################################] 100%
   (80/80) instalando qemu-desktop                    [########################################] 100%
   ```

3. Instale o binário oficial do driver `docker-machine-driver-kvm2`:
   ```zsh
   curl -LO https://storage.googleapis.com/minikube/releases/latest/docker-machine-driver-kvm2
   sudo install -o root -g root -m 0755 docker-machine-driver-kvm2 /usr/local/bin/docker-machine-driver-kvm2
   rm docker-machine-driver-kvm2
   ```
   **Retorno esperado:**
   ```text
     % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
   100 15.2M  100 15.2M    0     0  8.50M      0  0:00:01  0:00:01 --:--:-- 8.50M
   ```

4. Adicione o usuário aos grupos do hipervisor e ative os sockets modulares do Libvirt no Arch Linux:
   ```zsh
   sudo usermod -aG libvirt,kvm $USER
   sudo systemctl enable --now virtqemud.socket virtnetworkd.socket virtstoraged.socket virtlogd.socket
   ```
   **Retorno esperado:**
   ```text
   Created symlink '/etc/systemd/system/sockets.target.wants/virtqemud.socket' -> '/usr/lib/systemd/system/virtqemud.socket'.
   ```

5. Defina a URI padrão do sistema para o Libvirt e inicialize a rede virtual `default`:
   ```zsh
   echo 'export LIBVIRT_DEFAULT_URI="qemu:///system"' >> ~/.zshrc
   echo 'export LIBVIRT_DEFAULT_URI="qemu:///system"' >> ~/.bashrc
   export LIBVIRT_DEFAULT_URI="qemu:///system"
   sudo virsh net-autostart default
   sudo virsh net-start default
   newgrp libvirt
   ```
   **Retorno esperado:**
   ```text
   Network default marked as autostarted
   Network default started
   ```

---

### 2C. Validação do Hipervisor e Liberação de Roteamento IPv4 (Ambos os Sistemas)

1. Teste a comunicação com o Libvirt:
   ```bash
   virsh list --all
   ```
   **Retorno esperado:**
   ```text
    Id   Name   State
   --------------------
   ```

2. Habilite o encaminhamento de pacotes IPv4 no kernel e libere a interface virtual `virbr0` no `iptables` (evita que o firewall do Docker bloqueie o acesso à internet da VM do Minikube e cause `Init:ImagePullBackOff`):
   ```bash
   sudo sysctl -w net.ipv4.ip_forward=1
   echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/30-ipforward.conf
   sudo iptables -P FORWARD ACCEPT
   sudo iptables -I FORWARD 1 -i virbr0 -j ACCEPT
   sudo iptables -I FORWARD 1 -o virbr0 -j ACCEPT
   ```
   **Retorno esperado:**
   ```text
   net.ipv4.ip_forward = 1
   ```

---

## Passo 3: Instalar `kubectl`, `minikube` e `px` (Pixie CLI)

1. Baixe e instale o `kubectl`:
   ```bash
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
   rm kubectl
   kubectl version --client
   ```
   **Retorno esperado:**
   ```text
   Client Version: v1.35.x
   Kustomize Version: v5.x.x
   ```

2. Baixe e instale o `minikube`:
   ```bash
   curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
   sudo install -o root -g root -m 0755 minikube-linux-amd64 /usr/local/bin/minikube
   rm minikube-linux-amd64
   minikube version
   ```
   **Retorno esperado:**
   ```text
   minikube version: v1.38.1
   commit: ...
   ```

3. Instale a CLI oficial do Pixie (`px`) e disponibilize-a globalmente em `/usr/local/bin`:
   ```bash
   bash -c "$(curl -fsSL https://withpixie.ai/install.sh)"
   sudo install -o root -g root -m 0755 $HOME/bin/px /usr/local/bin/px
   px version
   ```
   *(Durante a instalação, digite `y` para aceitar os termos e pressione `ENTER` para confirmar o caminho padrão).*

   **Retorno esperado:**
   ```text
   Pixie CLI
   0.8.8+Distribution.042e356...
   ```

---

## Passo 4: Provisionar o Cluster Minikube com KVM2 e Flannel

> **Atenção ao Dimensionamento de Memória RAM:**
> * Se a sua máquina física possui **16 GB de RAM ou mais**, utilize `--memory=7000mb` ou `--memory=8000mb`.
> * Se a sua máquina física possui **8 GB de RAM** (~7676 MiB utilizáveis), utilize obrigatoriamente **`--memory=4096mb` (ou no máximo `4500mb`)**. Alocar 7000 MB em um host de 8 GB acionará o *OOM-Killer* do kernel Linux quando os microsserviços subirem, matando o processo `qemu-system-x86` e gerando o erro `dial tcp 192.168.39.x:8443: connect: no route to host`.

1. Inicialize o cluster especificando o driver `kvm2`, a rede `flannel` e o perfil `pixie-cluster`:
   ```bash
   minikube start \
     --driver=kvm2 \
     --cni=flannel \
     --cpus=4 \
     --memory=4096mb \
     -p=pixie-cluster
   ```
   **Retorno esperado:**
   ```text
   😄  [pixie-cluster] minikube v1.38.1 on Arch
   ✨  Using the kvm2 driver based on user configuration
   👍  Starting "pixie-cluster" primary control-plane node in "pixie-cluster" cluster
   🔥  Creating kvm2 VM (CPUs=4, Memory=4096MB, Disk=20000MB) ...
   🐳  Preparing Kubernetes v1.35.1 on Docker 28.5.2 ...
   🔗  Configuring Flannel (Container Networking Interface) ...
   🔎  Verifying Kubernetes components...
   🌟  Enabled addons: storage-provisioner, default-storageclass
   🏄  Done! kubectl is now configured to use "pixie-cluster" cluster and "default" namespace by default
   ```

2. Teste a conectividade externa de dentro da VM do Minikube:
   ```bash
   minikube ssh -p pixie-cluster -- ping -c 3 8.8.8.8
   ```
   **Retorno esperado:**
   ```text
   PING 8.8.8.8 (8.8.8.8): 56 data bytes
   64 bytes from 8.8.8.8: seq=0 ttl=115 time=14.2 ms
   --- 8.8.8.8 ping statistics ---
   3 packets transmitted, 3 received, 0% packet loss
   ```

3. Verifique se o nó está `Ready` e se o pod do Flannel está em execução:
   ```bash
   kubectl get nodes
   kubectl get pods -n kube-flannel
   ```
   **Retorno esperado:**
   ```text
   NAME            STATUS   ROLES           AGE   VERSION
   pixie-cluster   Ready    control-plane   2m    v1.35.1

   NAME                    READY   STATUS    RESTARTS   AGE
   kube-flannel-ds-28rxk   1/1     Running   0          2m
   ```
   *(Caso o nó permaneça em `NotReady` por falta do DaemonSet do Flannel, aplique manualmente: `kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml`).*

---

## Passo 5: Autenticar e Implantar o Pixie no Cluster

1. Realize a autenticação na nuvem do Pixie (Cosmic):
   ```bash
   px auth login --manual
   ```
   *(Abra o link exibido no terminal no seu navegador, faça login, copie o token gerado e cole no terminal).*

   **Retorno esperado:**
   ```text
   Authentication successful.
   ```

2. Gere uma chave de API permanente e persista-a no seu arquivo de configuração do shell (sem incluir os sinais `< >`):
   ```bash
   px api-key create
   ```
   **Retorno esperado:**
   ```text
   Pixie CLI
   Table ID: api_key
     ID                                    KEY                                         CREATED AT
     ab12cd34-...                          px-api-0f1292d4-fc7b-41c9-b70f-474e016fa147 ...
   ```

   Exporte a chave gerada:
   ```bash
   export PL_API_KEY="px-api-SUA-CHAVE-AQUI"
   echo 'export PL_API_KEY="px-api-SUA-CHAVE-AQUI"' >> ~/.zshrc
   echo 'export PL_API_KEY="px-api-SUA-CHAVE-AQUI"' >> ~/.bashrc
   ```

3. Implante o Pixie Vizier no cluster `pixie-cluster`:
   ```bash
   px deploy --cluster_name=pixie-cluster
   ```
   *(Confirme com `y` quando solicitado).*

   **Retorno esperado:**
   ```text
   Found 1 nodes
    ✔    Installing OLM CRDs
    ✔    Deploying OLM
    ✔    Deploying Pixie OLM Namespace
    ✔    Installing Vizier CRD
    ✔    Deploying OLM Catalog
    ✔    Deploying OLM Subscription
    ✔    Creating namespace
    ✔    Deploying Vizier
    ✔    Waiting for Cloud Connector to come online
    ✔    Wait for PEMs/Kelvin
   ```
   > **Nota Técnica:** Caso apareça o alerta `Detected missing kernel headers on your cluster's nodes`, ele pode ser ignorado com segurança no driver `kvm2`. O kernel da imagem KVM possui suporte nativo a BTF/CO-RE, permitindo que o `vizier-pem` injete as sondas eBPF diretamente na memória.

4. Verifique se todos os 6 pods do namespace `pl` estão em estado `Running`:
   ```bash
   kubectl get pods -n pl
   ```
   **Retorno esperado:**
   ```text
   NAME                                      READY   STATUS    RESTARTS   AGE
   kelvin-f7f6779c4-ztx79                    1/1     Running   0          3m
   pl-nats-0                                 1/1     Running   0          3m
   vizier-cloud-connector-5d4f675bc-2zxmt    1/1     Running   0          3m
   vizier-metadata-0                         1/1     Running   0          3m
   vizier-pem-lgt2r                          1/1     Running   0          3m
   vizier-query-broker-5654486f88-qnp9x      1/1     Running   0          3m
   ```

5. Confirme a saúde da conexão com a nuvem e do módulo coletor eBPF:
   ```bash
   px get clusters
   px get pems
   ```
   **Retorno esperado:**
   ```text
   CLUSTERNAME              ID         ...  STATUS
   pixie-cluster_65ceb541   c5bafeb8...     CS_HEALTHY

   NAME               ID         ...  STATUS
   vizier-pem-lgt2r   ...             AGENT_STATE_HEALTHY
   ```

---

## Passo 6: Implantar a Aplicação Google Online Boutique

1. Crie um namespace dedicado chamado `boutique`:
   ```bash
   kubectl create namespace boutique
   ```
   **Retorno esperado:**
   ```text
   namespace/boutique created
   ```

2. Aplique os manifestos oficiais da Google Online Boutique:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml -n boutique
   ```
   **Retorno esperado:**
   ```text
   deployment.apps/emailservice created
   service/emailservice created
   deployment.apps/checkoutservice created
   service/checkoutservice created
   deployment.apps/recommendationservice created
   ...
   deployment.apps/loadgenerator created
   ```

3. Acompanhe a inicialização dos microsserviços até atingirem `1/1 Running`:
   ```bash
   kubectl get pods -n boutique
   ```
   **Retorno esperado:**
   ```text
   NAME                                     READY   STATUS    RESTARTS   AGE
   adservice-854578d668-v2r7f               1/1     Running   0          2m
   cartservice-5bdbb48f5-rzrzg              1/1     Running   0          2m
   checkoutservice-56c9d4bf78-l5hsn         1/1     Running   0          2m
   currencyservice-85486c4d86-cq2ps         1/1     Running   0          2m
   emailservice-5fc68f4566-28rzw            1/1     Running   0          2m
   frontend-58759ddc44-v2mh6                1/1     Running   0          2m
   loadgenerator-d759f45db-85xls            1/1     Running   0          2m
   paymentservice-84d6969dcd-tktzp          1/1     Running   0          2m
   productcatalogservice-85686fc5d-k287p    1/1     Running   0          2m
   recommendationservice-574c444bdd-dx8rf   1/1     Running   0          2m
   redis-cart-67c6cc55cb-g4skp              1/1     Running   0          2m
   shippingservice-d9fd7754b-2hlhc          1/1     Running   0          2m
   ```

4. Exponha o serviço `frontend-external` localmente para acessar a loja pelo navegador e disparar transações manuais (`POST /cart` e `POST /cart/checkout`):
   ```bash
   kubectl port-forward svc/frontend-external 8080:80 -n boutique
   ```
   **Retorno esperado:**
   ```text
   Forwarding from 127.0.0.1:8080 -> 8080
   Forwarding from [::1]:8080 -> 8080
   ```
   *(Mantenha este terminal aberto e acesse `http://localhost:8080` no navegador para navegar pelos produtos, adicionar itens ao carrinho e concluir pedidos).*

---

## Passo 7: Extração de Métricas de Rede (Scripts Nativos e PxL)

Abra um **novo terminal** para executar as análises de tráfego capturadas pelo eBPF.

### 7.1. Inspeção de Requisições HTTP/gRPC e DNS Nativos

1. Auditar chamadas HTTP/gRPC em tempo real (Camada 7):
   ```bash
   px run px/http_data
   ```
   **Retorno esperado:**
   ```text
   TIME_                 REMOTE_ADDR   REQ_METHOD   REQ_PATH                RESP_STATUS   LATENCY   SVC
   2026-11-03 18:15:00   10.244.0.1    GET          /product/66VCHSJNUP     200           12.73ms   boutique/frontend
   2026-11-03 18:15:04   10.244.0.1    POST         /cart                   200           3.65ms    boutique/frontend
   2026-11-03 18:15:10   10.244.0.1    POST         /cart/checkout          200           44.89ms   boutique/frontend
   ```

2. Auditar resolução de nomes e latência do CoreDNS:
   ```bash
   px run px/dns_data
   ```
   **Retorno esperado:**
   ```text
   TIME_                 SOURCE                            DESTINATION   LATENCY    QUERIES
   2026-11-03 17:43:02   boutique/cartservice-69675...     10.96.0.10    54.0 µs    [{"name":"redis-cart.boutique.svc.cluster.local..."}]
   2026-11-03 17:43:13   boutique/cartservice-69675...     10.96.0.10    272.5 µs   [{"name":"redis-cart.boutique.svc.cluster.local..."}]
   ```

---

### 7.2. Script PxL Customizado 1: Matriz de Comunicação L7 (`matriz_comunicacao.pxl`)

Este script agrega todas as requisições HTTP/gRPC do namespace `boutique` por serviço, método e rota, convertendo as latências média, máxima e mínima de nanosegundos para milissegundos.

1. Crie o arquivo `matriz_comunicacao.pxl`:
   ```bash
   cat << 'EOF' > matriz_comunicacao.pxl
   import px

   # Filtra eventos HTTP/gRPC dos últimos 5 minutos
   df = px.DataFrame(table='http_events', start_time='-5m')

   # Vincula o serviço e filtra o namespace boutique
   df.service = df.ctx['service']
   df = df[px.contains(df.ctx['namespace'], 'boutique')]

   # Agrega por serviço de destino, rota e método HTTP
   agg_df = df.groupby(['service', 'req_method', 'req_path']).agg(
       total_requisicoes=('latency', px.count),
       latencia_media_ns=('latency', px.mean),
       latencia_max_ns=('latency', px.max),
       latencia_min_ns=('latency', px.min)
   )

   # Converte nanosegundos (ns) para milissegundos (ms)
   agg_df.latencia_media_ms = agg_df.latencia_media_ns / 1000000.0
   agg_df.latencia_max_ms = agg_df.latencia_max_ns / 1000000.0
   agg_df.latencia_min_ms = agg_df.latencia_min_ns / 1000000.0

   # Formata a tabela final
   resultado = agg_df[['service', 'req_method', 'req_path', 'total_requisicoes', 'latencia_media_ms', 'latencia_max_ms', 'latencia_min_ms']]

   px.display(resultado, 'Matriz_Comunicacao_Boutique')
   EOF
   ```

2. Execute o script:
   ```bash
   px run -f matriz_comunicacao.pxl
   ```
   **Retorno esperado:**
   ```text
   Table ID: Matriz_Comunicacao_Boutique
   SERVICE             REQ_METHOD   REQ_PATH                TOTAL_REQUISICOES   LATENCIA_MEDIA_MS   LATENCIA_MAX_MS   LATENCIA_MIN_MS
   boutique/frontend   GET          /_healthz               60                  0.52                1.25              0.22
   boutique/frontend   GET          /                       5                   25.93               36.44             20.35
   boutique/frontend   GET          /product/66VCHSJNUP     1                   12.73               12.73             12.73
   boutique/frontend   GET          /cart                   7                   18.35               31.34             9.53
   boutique/frontend   POST         /cart                   2                   3.65                4.10              3.21
   boutique/frontend   POST         /cart/checkout          3                   44.89               94.30             17.57
   ```

---

### 7.3. Script PxL Customizado 2: Consumo de Banda e Erros em Camada 4 (`rede_l4_stats.pxl`)

Este script consulta a tabela `network_stats` para medir o tráfego bruto (RX/TX em Megabytes) e checar a ocorrência de erros na camada de transporte em cada pod da loja.

1. Crie o arquivo `rede_l4_stats.pxl`:
   ```bash
   cat << 'EOF' > rede_l4_stats.pxl
   import px

   # Carrega métricas dos sockets da tabela network_stats dos últimos 5 minutos
   df = px.DataFrame(table='network_stats', start_time='-5m')
   df.pod = df.ctx['pod']
   df = df[px.contains(df.ctx['namespace'], 'boutique')]

   # Agrupa por pod para auditar consumo de banda de rede
   pod_net = df.groupby(['pod']).agg(
       rx_bytes_total=('rx_bytes', px.sum),
       tx_bytes_total=('tx_bytes', px.sum),
       erros_rx=('rx_errors', px.sum),
       erros_tx=('tx_errors', px.sum)
   )

   # Converte bytes para Megabytes
   pod_net.rx_mb = pod_net.rx_bytes_total / (1024 * 1024)
   pod_net.tx_mb = pod_net.tx_bytes_total / (1024 * 1024)

   px.display(pod_net, 'Consumo_Banda_Rede_L4')
   EOF
   ```

2. Execute o script:
   ```bash
   px run -f rede_l4_stats.pxl
   ```
   **Retorno esperado:**
   ```text
   Table ID: Consumo_Banda_Rede_L4
   POD                                         RX_BYTES_TOTAL   TX_BYTES_TOTAL   ERROS_RX   ERROS_TX   RX_MB   TX_MB
   boutique/frontend-58759ddc44-v2mh6          70.1 MB          62.3 MB          0          0          70.09   62.29
   boutique/emailservice-5fc68f4566-28rzw      69.7 MB          52.7 MB          0          0          69.73   52.75
   boutique/recommendationservice-574c444...   59.5 MB          40.7 MB          0          0          59.46   40.67
   boutique/shippingservice-d9fd7754b-2hlhc    56.4 MB          37.9 MB          0          0          56.40   37.88
   boutique/productcatalogservice-85686fc...   54.9 MB          59.3 MB          0          0          54.91   59.26
   boutique/checkoutservice-56c9d4bf78-l5hsn   48.9 MB          35.3 MB          0          0          48.93   35.26
   boutique/cartservice-5bdbb48f5-rzrzg        43.0 MB          31.3 MB          0          0          42.95   31.29
   ```

---

## Passo 8: Visualização Gráfica na Web (Cosmic / Pixie Live UI)

1. Acesse **[https://work.getcosmic.ai](https://work.getcosmic.ai)** (ou `https://work.withpixie.ai`).
2. No seletor superior esquerdo (`cluster`), selecione **`pixie-cluster`**.
3. No seletor **`script`**, escolha:
   * **`px/namespace`** (definindo `namespace: boutique`): Exibe o **HTTP Service Map** (grafo de tráfego L7 com percentis $P_{50}/P_{90}/P_{99}$ e taxa de erros).
   * **`px/dns_flow_graph`**: Exibe o **DNS Flow Graph** mapeando as consultas de *Service Discovery* entre os pods e o `kube-dns`.
   * **`Scratch Pad`**: Permite colar os códigos dos arquivos `matriz_comunicacao.pxl` e `rede_l4_stats.pxl` e clicar no botão **RUN** para gerar as tabelas visuais diretamente no navegador.

---

## Passo 9: Rotina Diária de Inicialização, Pausa e Recuperação de Falhas

### 9.1. Encerrar o Laboratório com Segurança
Ao finalizar os testes, pare a máquina virtual ordenadamente para liberar memória RAM e preservar o disco virtual:

```bash
minikube stop -p pixie-cluster
```
**Retorno esperado:**
```text
✋  Stopping node "pixie-cluster"  ...
🛑  1 node stopped.
```

### 9.2. Retomar o Laboratório (Cold Boot)
Ao ligar o computador novamente, basta iniciar o perfil existente e reaplicar a regra de encaminhamento do `iptables`:

```bash
minikube start -p pixie-cluster --memory=4096mb
sudo iptables -P FORWARD ACCEPT
sudo iptables -I FORWARD 1 -i virbr0 -j ACCEPT
sudo iptables -I FORWARD 1 -o virbr0 -j ACCEPT
```

### 9.3. Solução Rápida de Problemas (Troubleshooting)

* **Erro `Unable to connect to the server: dial tcp 192.168.39.x:8443: connect: no route to host`:**
  A máquina virtual KVM foi desligada pelo *OOM-Killer* por falta de RAM no host. Redimensione o limite máximo de memória da VM diretamente no Libvirt para `4096 MB` e religue o cluster:
  ```bash
  sudo virsh setmaxmem pixie-cluster 4194304 --config
  sudo virsh setmem pixie-cluster 4194304 --config
  minikube start -p pixie-cluster --memory=4096mb
  ```
* **Erro `Cluster is unhealthy (CS_UNHEALTHY)` na interface web:**
  Reinicie o conector de nuvem e o broker de consultas no namespace `pl`:
  ```bash
  kubectl rollout restart deployment vizier-cloud-connector vizier-query-broker -n pl
  ```
* **Pods duplicados em `Pending` ou `ContainerStatusUnknown` após queda de energia:**
  Limpe os pods órfãos do namespace `boutique`:
  ```bash
  kubectl delete pods -n boutique --field-selector status.phase=Failed --force --grace-period=0
  kubectl delete pods -n boutique --field-selector status.phase=Unknown --force --grace-period=0
  ```
