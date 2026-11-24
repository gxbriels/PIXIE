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

   > **Recomendado (replicabilidade):** o arquivo acima aponta para o branch `main`, que muda a cada release da Google. Para que todas as turmas usem exatamente a mesma versão, salve uma cópia local dentro da pasta `scripts/` do repositório e aplique a partir dela. O script `falhas.sh` (Passo 10) usa essa cópia automaticamente quando ela existe:
   > ```bash
   > curl -L -o scripts/kubernetes-manifests.yaml \
   >   https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml
   > kubectl apply -n boutique -f scripts/kubernetes-manifests.yaml
   > ```

2.1. **Obrigatório em VMs de 4 GB:** reduza as reservas (*requests*) de CPU e memória dos microsserviços. Os manifestos oficiais reservam mais memória do que sobra na VM depois do Pixie: sem este passo o nó chega a ~95% de memória reservada e alguns pods ficam presos em `Pending` com `Insufficient memory`, em geral o **`loadgenerator`**. Sem ele **não existe tráfego na loja** e todas as tabelas de latência do Pixie ficam vazias, sem nenhum aviso de erro. O comando altera só a reserva usada no agendamento; os limites (*limits*) continuam os originais.
   ```bash
   kubectl set resources deployment --all -n boutique --requests=cpu=20m,memory=32Mi
   ```
   **Retorno esperado:**
   ```text
   deployment.apps/adservice resource requirements updated
   deployment.apps/cartservice resource requirements updated
   ...
   deployment.apps/shippingservice resource requirements updated
   ```
   Para conferir a ocupação do nó: `kubectl describe node pixie-cluster | grep -A6 "Allocated resources"`.

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

3.1. Confirme que o gerador de tráfego sintético (Locust) está de fato enviando requisições. Sem ele, os experimentos de falha não produzem dados:
   ```bash
   kubectl logs -n boutique deploy/loadgenerator --tail=15
   ```
   **Retorno esperado** (a contagem `# reqs` deve crescer a cada atualização):
   ```text
   Type     Name                       # reqs      # fails |    Avg     Min     Max    Med |   req/s  failures/s
   GET      /                              10     0(0.00%) |     40      20      90     35 |    1.00        0.00
   GET      /product/66VCHSJNUP             2     0(0.00%) |     36      33      40     35 |    0.20        0.00
   ...
            Aggregated                     24     0(0.00%) |     38      18     110     35 |    2.10        0.00
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

> **Se o laboratório ficou muitos dias desligado** (testado após ~3 semanas parado), execute a sequência completa abaixo antes de qualquer outra coisa. No Arch Linux, os sockets do Libvirt e a rede `default` podem não subir sozinhos:
> ```bash
> sudo systemctl start virtqemud.socket virtnetworkd.socket virtstoraged.socket virtlogd.socket   # Arch
> sudo systemctl start libvirtd                                                                   # Ubuntu/Debian
> export LIBVIRT_DEFAULT_URI="qemu:///system"
> virsh list --all                  # a VM "pixie-cluster" deve aparecer como "shut off"
> sudo virsh net-start default      # "already active" também é um resultado válido
> sudo sysctl -w net.ipv4.ip_forward=1
> sudo iptables -P FORWARD ACCEPT
> sudo iptables -I FORWARD 1 -i virbr0 -j ACCEPT
> sudo iptables -I FORWARD 1 -o virbr0 -j ACCEPT
> minikube start -p pixie-cluster
> kubectl config use-context pixie-cluster
> kubectl get pods -A               # aguarde todos em Running (3 a 5 min)
> px get viz                        # o cluster deve estar CS_HEALTHY
> kubectl get pods -n boutique      # confira se há pods Pending (ver 9.3)
> ```

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
* **Pods em `Pending` com `Insufficient memory` (`kubectl describe pod <nome> -n boutique` → seção *Events*):**
  A memória reservada no nó se esgotou. Reduza os *requests* (Passo 6, item 2.1) e apague os pods `Pending` que sobrarem de rollouts antigos:
  ```bash
  kubectl set resources deployment --all -n boutique --requests=cpu=20m,memory=32Mi
  kubectl delete pod -n boutique <nome-do-pod-pending>
  ```
  Se a máquina física tiver **16 GB ou mais**, a solução definitiva é aumentar a VM para 8 GB:
  ```bash
  minikube stop -p pixie-cluster
  sudo virsh setmaxmem pixie-cluster 8388608 --config
  sudo virsh setmem    pixie-cluster 8388608 --config
  sed -i 's/"Memory": *[0-9]*/"Memory": 8192/' ~/.minikube/profiles/pixie-cluster/config.json
  minikube start -p pixie-cluster
  ```
* **Pares de pods (um `Running` antigo + um `Pending` novo) após `kubectl rollout restart`:**
  O Kubernetes só encerra o pod antigo depois que o novo fica pronto. Numa VM sem memória livre o novo nunca é agendado e o rollout fica travado. Aplique a correção acima. **Evite `kubectl rollout restart deployment -n boutique` (todos de uma vez)**: em VM de 4 GB isso deixa a loja indisponível por vários minutos.
* **Tabelas de latência do Pixie vazias, só com health checks (`/_healthz`):**
  Não há tráfego na loja. Verifique se o `loadgenerator` está `Running` e se o log dele mostra requisições (Passo 6, item 3.1).
* **Todas as rotas retornando `500` com latência de ~5 s:**
  Sintoma de falha em cascata do `redis-cart` (o carrinho é consultado por todas as páginas). Confira com `kubectl get pods -n boutique | grep redis` e, se necessário, `kubectl scale deployment/redis-cart -n boutique --replicas=1`.
* **`error: Metrics API not available` no `kubectl top`:**
  O metrics-server leva 1 a 2 minutos para subir depois de habilitado. Confira com `kubectl get pods -n kube-system | grep metrics`. Se ficar `Pending`, é falta de memória (ver acima).
* **`RTNETLINK answers: Operation not permitted` ao injetar latência/perda de rede:**
  O container de debug herdou o usuário não-root do pod. Use a versão do `scripts/falhas.sh` deste repositório, que cria o container efêmero com perfil customizado (`runAsUser: 0` + `NET_ADMIN`). A saída correta precisa conter `TC_OK` e `qdisc netem`.

---

## Passo 10: Injeção Controlada de Falhas (Fault Injection)

Este passo provoca falhas intencionais na Online Boutique **sem alterar o código-fonte**, atuando no Kubernetes, na rede dos pods e no nó, e usa o Pixie para observar como cada falha se propaga entre os microsserviços.

### 10.1. Arquivos utilizados (pasta `scripts/`)

| Arquivo | Função |
|---|---|
| `scripts/falhas.sh` | Injeta e desfaz as falhas. Registra cada ação com data, hora e fuso em `resultados/experimentos.csv` |
| `scripts/dashboard_falhas.pxl` | Painel PxL com o resumo das falhas (Passo 11) |
| `scripts/diag_http.pxl` / `scripts/diag_proc.pxl` | Diagnósticos de quais dados o Pixie está coletando (Passo 12) |
| `scripts/kubernetes-manifests.yaml` | Cópia local opcional do manifesto da Boutique (Passo 6, item 2) |

As ferramentas de falha rodam **dentro do cluster** (imagens `nicolaka/netshoot` com `tc`/netem e `alexeiled/stress-ng`). Não é preciso instalar nada a mais no host, seja Ubuntu ou Arch.

### 10.2. Preparação (uma vez por sessão)

1. Torne o script executável e veja os comandos disponíveis:
   ```bash
   chmod +x scripts/falhas.sh
   ./scripts/falhas.sh ajuda
   ```
2. Garanta os *requests* reduzidos (ver Passo 6, item 2.1):
   ```bash
   ./scripts/falhas.sh recursos
   ```
3. Baixe antecipadamente as imagens das ferramentas dentro da VM, para não esperar no meio de um experimento:
   ```bash
   minikube ssh -p pixie-cluster -- "docker pull nicolaka/netshoot && docker pull alexeiled/stress-ng"
   ```
4. Verifique se o kernel da VM possui o módulo `netem` (necessário para as falhas de rede):
   ```bash
   minikube ssh -p pixie-cluster -- "sudo modprobe sch_netem && lsmod | grep netem"
   ```
   **Retorno esperado:** uma linha contendo `sch_netem`.
5. Habilite o metrics-server para medir CPU e memória por pod. Ele substitui a tabela `process_stats` do Pixie, que não funcionou neste ambiente (ver Passo 12):
   ```bash
   minikube addons enable metrics-server -p pixie-cluster
   kubectl top pods -n boutique      # aguarde 1 a 2 min após habilitar
   ```
   **Retorno esperado:**
   ```text
   NAME                                     CPU(cores)   MEMORY(bytes)
   adservice-54c9f8bdcf-jltnp               2m           92Mi
   cartservice-6b67d48744-g4jp9             7m           71Mi
   ...
   ```
   > O metrics-server também reserva memória. Em VM de 4 GB, se outro pod ficar `Pending` depois de habilitá-lo, desabilite-o durante os experimentos: `minikube addons disable metrics-server -p pixie-cluster`.

### 10.3. Protocolo experimental (siga para cada cenário)

Injete **uma falha por vez**. O painel analisa sempre os últimos 5 minutos, então cada captura deve cobrir exatamente uma fase:

```bash
mkdir -p resultados
./scripts/falhas.sh marco baseline
sleep 300; px run -f scripts/dashboard_falhas.pxl -o json > resultados/cN_baseline.json

./scripts/falhas.sh <comando-da-falha> <args>
sleep 300; px run -f scripts/dashboard_falhas.pxl -o json > resultados/cN_falha.json

./scripts/falhas.sh <comando-que-desfaz>        # ver tabela abaixo
./scripts/falhas.sh marco recuperacao
sleep 300; px run -f scripts/dashboard_falhas.pxl -o json > resultados/cN_recuperacao.json
```
Em cada fase, salve também `kubectl top pods -n boutique > resultados/cN_<fase>_top.txt` e prints do painel na interface web. Não injete duas falhas sobrepostas: isso torna impossível atribuir cada efeito à sua causa.

### 10.4. Catálogo de cenários

| # | Cenário | Injetar | Desfazer | Onde atua | Sinal esperado no Pixie |
|---|---|---|---|---|---|
| 1 | Latência na aplicação | `./scripts/falhas.sh catalogo-lento 500ms` | `./scripts/falhas.sh reset` | Variável `EXTRA_LATENCY` (recurso nativo da Boutique) | p99 de `GET /` e `GET /product/*` sobe; vazão cai; **nenhum erro** |
| 2 | Latência de rede | `./scripts/falhas.sh latencia currencyservice 300ms 50ms` | `./scripts/falhas.sh rede-reset currencyservice` | `tc netem` na `eth0` do pod (container efêmero) | p99 de quase todas as rotas sobe (a conversão de moeda está em todas as páginas) |
| 3 | Perda de pacotes | `./scripts/falhas.sh perda cartservice 20%` | `./scripts/falhas.sh rede-reset cartservice` | `tc netem` | Picos irregulares de latência (retransmissões TCP) |
| 4 | Serviço indisponível | `./scripts/falhas.sh derrubar paymentservice` | `./scripts/falhas.sh restaurar paymentservice` | Réplicas = 0 | `POST /cart/checkout` com **500**; o par checkoutservice → paymentservice some do fluxo L4 |
| 5 | Falha em cascata | `./scripts/falhas.sh derrubar redis-cart` | `./scripts/falhas.sh restaurar redis-cart` | Réplicas = 0 | **Todas** as rotas com 500 e latência de ~5 s (timeout) |
| 6 | Stress de CPU (vizinho barulhento) | `./scripts/falhas.sh cpu-stress 4 300` | termina sozinho em 300 s, ou `./scripts/falhas.sh reset` | Pod `stress-ng` no nó | Latência sobe em todas as rotas; ver `kubectl top` |
| 7 | Throttling de CPU | `./scripts/falhas.sh cpu-limite currencyservice 20` | `./scripts/falhas.sh reset currencyservice` | Limite de 20 millicores | Degradação concentrada nas rotas que usam o serviço |
| 8 | Falta de memória | `./scripts/falhas.sh mem-limite currencyservice 32` | `./scripts/falhas.sh reset currencyservice` | Limite de 32 Mi | `OOMKilled` / reinícios; erros intermitentes |
| 9 | Alta demanda | `./scripts/falhas.sh carga 150 15 2` | `./scripts/falhas.sh reset` | Usuários do Locust e réplicas do loadgenerator | RPS e p99 sobem; combine com o cenário 7 para mostrar saturação |
| 10 | Chaos monkey | `./scripts/falhas.sh matar-pods cartservice 5 30` | termina sozinho | Apaga o pod a cada 30 s | Rajadas de erro a cada reinício |

> **Cuidados:** a VM tem pouca memória. No `mem-stress`, não passe de ~1024 MB, senão o OOM-Killer derruba a VM inteira (erro `no route to host`, ver 9.3). O stress de CPU também atinge o próprio PEM do Pixie, o que é um ponto a discutir na análise.
>
> **Status dos testes (24/11/2026):** os cenários 1 e 5 foram executados com sucesso e o painel registrou os efeitos (ver 10.5). Os cenários de rede (2 e 3) dependem da correção de permissão do `tc` descrita em 9.3 e ainda precisam ser validados. Os demais seguem o mesmo mecanismo do Kubernetes dos cenários testados.

### 10.5. Resultados de referência

Use estes números para conferir se o seu ambiente se comporta de forma parecida.

**Cenário 1, `EXTRA_LATENCY=500ms` no productcatalogservice** (rota agregada do frontend, intervalos de 10 s, 10 usuários do Locust):

| Fase | p99 típico | Requisições a cada 10 s | Erros | TX do frontend em 5 min |
|---|---|---|---|---|
| Baseline | ~41 ms | ~26 | ~0 | 9,0 MB |
| Falha | ~4.500 ms | ~15 | 0 | 5,5 MB |
| Recuperação | ~38 ms | ~27 | 0 | 9,2 MB |

Leitura do resultado:
* **Amplificação:** 500 ms injetados num único serviço viraram ~4,5 s para o usuário, porque cada página chama o catálogo várias vezes em sequência.
* **Queda de vazão confirmada em duas camadas:** na L7 (menos requisições) e na L4 (menos bytes transmitidos).
* **Degradação silenciosa:** taxa de erro zero e probes saudáveis durante toda a falha. Só a medição de latência por eBPF revelou o problema.

**Cenário 5, queda do `redis-cart`:** todas as rotas (`GET /`, `GET /product/*`, `GET /cart`, `POST /cart`, `POST /cart/checkout`) retornaram `500 Internal Server Error` com latência entre 5 e 6 s (timeout). O pod sumiu das tabelas L4, enquanto os demais continuavam `Running` no Kubernetes.

---

## Passo 11: Painel de Falhas em PxL (`scripts/dashboard_falhas.pxl`)

1. Execute pelo terminal, de uma vez ou em modo contínuo:
   ```bash
   px run  -f scripts/dashboard_falhas.pxl
   px live -f scripts/dashboard_falhas.pxl      # atualiza sozinho
   ```
   Na web (**work.getcosmic.ai**), selecione o cluster, escolha **Scratch Pad**, cole o conteúdo do arquivo e clique em **RUN**.

2. Tabelas geradas:

| Tabela | Conteúdo | Uso na análise |
|---|---|---|
| `Ranking_Rotas_Frontend` | Requisições, RPS, erros, p50/p90/p99 e `score_risco` por rota (`/product/<id>` agrupado como `/product/*`) | Cada rota depende de um conjunto de serviços. A rota mais degradada aponta onde está a falha. Em operação normal, `POST /cart/checkout` lidera o ranking por ser a rota que atravessa mais serviços |
| `Serie_Temporal_10s` | p99 e taxa de erro por rota a cada 10 s | Curva de baseline → falha → recuperação |
| `Ultimos_Erros` | Requisições com HTTP ≥ 400, com caminho, status e mensagem | Identificar quais rotas falharam e quando |
| `Fluxo_L4_Servicos` | Bytes/s de requisição e de resposta por par origem → destino (tabela `conn_stats`) | Mostra o tráfego **gRPC interno** mesmo sem decodificá-lo (ver Passo 12) |
| `Rede_L4_Pods` | MB recebidos/enviados, descartes e erros de interface por pod na janela | Vazão por pod; pods ausentes indicam indisponibilidade |

   `score_risco = 2 × taxa_de_erro(%) + p99(ms) / 10`. É uma heurística definida pelo grupo, e os pesos devem ser justificados no relatório.

3. **Retorno esperado** (`Ranking_Rotas_Frontend`, operação normal):
   ```text
   ROTA                 SCORE_RISCO  REQUISICOES  RPS   ERROS  TAXA_ERRO_PCT  P50_MS  P90_MS  P99_MS
   POST /cart/checkout  41.11        35           0.12  0      0              31.02   39.64   411.1
   GET /                20.69        77           0.26  0      0              24.15   40.68   206.9
   GET /product/*       12.59        375          1.25  0      0              20.70   40.68   125.9
   GET /cart            7.74         177          0.59  0      0              16.42   37.18   77.4
   POST /cart           0.87         85           0.28  0      0              2.41    3.97    8.7
   POST /setCurrency    0.85         58           0.19  0      0              2.87    6.26    8.5
   ```

---

## Passo 12: Limitações Observadas e Diagnóstico da Coleta

Durante os experimentos, foram identificadas limitações do Pixie neste ambiente (Minikube kvm2 + VM de 4 GB). Elas não invalidam a análise, mas definiram o desenho do painel e devem ser citadas no relatório.

1. **O gRPC (HTTP/2) entre os microsserviços não é decodificado.** A tabela `http_events` contém apenas o HTTP/1.1 do `frontend`. Para confirmar:
   ```bash
   px run -f scripts/diag_http.pxl
   kubectl logs -n pl -l name=vizier-pem --tail=500 | grep "ConnTracker statistics" | tail -1
   ```
   **Retorno observado:** `diag_http` com uma única linha (`boutique/frontend`, `trace_role=2`, `major_version=1`), e nos logs do PEM algo como `kProtocolHTTP2=4 ... kProtocolUnknown=385`. Quase todas as conexões gRPC são classificadas como protocolo desconhecido. A causa provável é a compressão de cabeçalhos do HTTP/2 (HPACK) em conexões de longa duração. **Contorno:** o tráfego interno é medido na camada L4 pela tabela `conn_stats` (`Fluxo_L4_Servicos`), que não depende de decodificar o protocolo.

2. **A tabela `process_stats` (CPU/memória por processo) fica vazia.**
   ```bash
   px run -f scripts/diag_proc.pxl
   ```
   **Retorno observado:** tabela sem linhas. **Contorno:** CPU e memória por pod via `kubectl top pods -n boutique` (metrics-server, Passo 10.2).

3. **Perda de eventos sob carga.** Os logs do PEM registraram `kLossMMapEvent=13636`: eventos descartados do buffer entre kernel e espaço de usuário. A captura por eBPF não é 100% sem perdas numa VM com poucos recursos, então em cenários de carga alta as contagens absolutas são uma estimativa por baixo.

4. **Permissões para injetar falhas de rede.** Os pods da Boutique rodam como não-root. Injetar `tc netem` exige um container efêmero com `runAsUser: 0` e `NET_ADMIN` (já tratado em `scripts/falhas.sh`).
