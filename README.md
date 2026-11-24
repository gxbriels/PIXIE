# Observabilidade Profunda de Redes e Análise de Falhas em Microsserviços com eBPF

## 📌 Propósito do Projeto
Este repositório reúne os estudos, scripts analíticos (PxL) e guias de implantação desenvolvidos para a disciplina de **Laboratório de Pesquisa I e II** do curso de Bacharelado em Sistemas de Informação no **IFES — Campus Serra**. 

O objetivo central da pesquisa é investigar a observabilidade em nível de núcleo do sistema operacional (*Kernel Space*) aplicada a arquiteturas de microsserviços orquestradas por Kubernetes. A pesquisa evoluiu de um perfilamento geral de recursos para uma **análise aprofundada do tráfego de rede em múltiplas camadas (L4, L7 e DNS)** e o estudo do comportamento da malha de serviços mediante a **implantação controlada de erros e anomalias (Fault Injection)**.

Através da interceptação transparente via **eBPF**, estabelecemos uma linha de base (*baseline*) quantitativa de comunicação entre microsserviços para, em seguida, injetar falhas (atrasos de rede, indisponibilidade de réplicas, erros HTTP e sobrecarga de transações) e auditar como a degradação se propaga pela topologia distribuída sem a necessidade de *sidecars* ou alterações no código-fonte.

---

## 🧠 Arquitetura e Tecnologias Utilizadas

* **eBPF (Extended Berkeley Packet Filter):** Motor tecnológico do laboratório. Permite executar programas verificados em *sandbox* diretamente no kernel do Linux, acoplando sondas dinâmicas (*kprobes* e *uprobes*) às rotinas do subsistema de sockets TCP/UDP. Isso viabiliza a captura de pacotes, métricas de transporte e payloads de aplicação (HTTP/1.1, HTTP/2, gRPC e DNS) com sobrecarga (*overhead*) mínima.
* **Pixie (Cosmic UI & PxL):** Plataforma de observabilidade *Cloud-Native* baseada em eBPF. Seus coletores locais (**PEM — Pixie Edge Module**) compilam sondas em tempo de execução e armazenam a telemetria nos próprios nós do cluster, permitindo consultas analíticas avançadas através da linguagem **PxL (*Pixie Language*)**.
* **Kubernetes (Minikube sobre Hipervisor KVM2):** A utilização inicial do driver `docker` impõe limitações de isolamento de contêineres e falhas no mapeamento dos cabeçalhos do kernel (`linux-headers`), inviabilizando a compilação de sondas de Camada 7. A arquitetura deste projeto adota obrigatoriamente o driver **`kvm2` (QEMU/KVM)** combinado ao plugin de rede **CNI Flannel (`--cni=flannel`)**, garantindo um kernel dedicado e a correlação exata de IPs entre pods e serviços.
* **Google Online Boutique (`microservices-demo`):** Aplicação alvo do estudo. Trata-se de um e-commerce completo composto por **11 microsserviços** poliglotas (Go, C#, Node.js, Python, Java) que se comunicam intensivamente via **gRPC** e **HTTP REST**, além de um gerador de tráfego sintético (`loadgenerator`) e persistência em cache (`redis-cart`). Mais informações sobre a aplicação em: [Repositório Boutique](https://github.com/googlecloudplatform/microservices-demo).

---

## 🔬 Metodologia de Análise de Rede

A coleta de dados e a avaliação experimental dividem-se em quatro eixos fundamentais:

1. **Topologia e Grafo de Dependências (Camada L7):** Mapeamento visual do fluxo de entrada (`frontend`) e das chamadas internas entre os microsserviços (`cartservice`, `checkoutservice`, `paymentservice`, `currencyservice`, etc.), medindo a taxa de requisições por segundo (RPS) e os percentis de latência.
2. **Matriz de Comunicação HTTP/gRPC:** Auditoria granular por rota (`GET /`, `GET /product/*`, `POST /cart`, `POST /cart/checkout`) e checagens de saúde do Kubelet (`GET /_healthz`), contrastando o tempo de resposta de operações de leitura em cache versus transações distribuídas síncronas.
3. **Telemetria de Transporte e Vazão (Camada L4):** Monitoramento do volume bruto de bytes recebidos (`RX`) e transmitidos (`TX`) por pod através da tabela `network_stats`, auditando a integridade da pilha virtual de rede por meio da contagem de pacotes descartados ou com erro (`rx_errors` / `tx_errors`).
4. **Descoberta de Serviços e Resolução DNS:** Rastreamento das consultas ao **CoreDNS** (`kube-dns`) para avaliar a latência de *Service Discovery* em microssegundos e o comportamento de encaminhamento para o gateway upstream do KVM.
5. **Injeção Controlada de Falhas (Fault Injection):** Provocação intencional de falhas, uma por vez, sem alterar o código-fonte, com coleta em três fases (*baseline* → falha → recuperação) de 5 minutos cada. As falhas atuam em quatro frentes:
   * **Aplicação:** latência artificial via `EXTRA_LATENCY`.
   * **Rede:** atraso e perda de pacotes com `tc netem` na interface do pod.
   * **Infraestrutura:** stress de CPU/memória com `stress-ng` e limites de CPU/memória.
   * **Disponibilidade e demanda:** réplicas zeradas, remoção periódica de pods e aumento da carga do `loadgenerator`.

   O efeito de cada falha é medido por um painel PxL próprio (`scripts/dashboard_falhas.pxl`), que gera um ranking de risco por rota, uma série temporal de latência p99 e taxa de erro, a lista dos erros e o fluxo L4 entre os serviços.

---

## 📊 Resultados Preliminares (24/11/2026)

* **Latência na aplicação (`EXTRA_LATENCY=500ms` no `productcatalogservice`):**
  * O p99 do frontend subiu de **~41 ms para ~4.500 ms**, uma amplificação de mais de 100 vezes. Cada página chama o catálogo várias vezes em sequência, e os atrasos se somam.
  * A vazão caiu cerca de 40%, confirmada em duas camadas: na L7 (menos requisições) e na L4 (TX do frontend de 9,0 MB para 5,5 MB).
  * A **taxa de erro ficou em zero** e os *probes* do Kubernetes continuaram saudáveis. Foi uma degradação silenciosa, visível apenas pela telemetria de latência via eBPF.
  * A recuperação foi completa ~30 s depois de remover a falha.
* **Falha em cascata (`redis-cart` indisponível):** **todas** as rotas passaram a retornar `500` com latência de ~5 s (timeout). Um único componente de infraestrutura derrubou a loja inteira, enquanto os demais pods seguiam `Running`.
* **Rota mais exposta a falhas:** `POST /cart/checkout` lidera o ranking de risco em operação normal. É a rota que atravessa mais microsserviços (checkout, payment, shipping, email, currency e cart).

---

## ⚠️ Limitações Identificadas

* **O gRPC/HTTP2 interno não foi decodificado pelo Pixie neste ambiente:** apenas o HTTP/1.1 do frontend aparece em `http_events`. Nos logs do PEM, só 4 conexões foram classificadas como HTTP/2, contra cerca de 385 classificadas como protocolo desconhecido. O tráfego entre os serviços foi medido na camada L4 (`conn_stats`).
* **A tabela `process_stats` ficou vazia:** CPU e memória por pod foram obtidos pelo `metrics-server` (`kubectl top`).
* **Perda de eventos sob carga:** o PEM registrou eventos descartados (`kLossMMapEvent`) numa VM de 4 GB.
* **Restrição de memória da VM:** com 4 GB, os *requests* padrão da Boutique somados ao Pixie esgotam a memória reservável do nó, e o `loadgenerator` fica em `Pending` sem gerar tráfego. A solução é reduzir os *requests* ou alocar 8 GB para a VM (detalhes no `installation.md`).


---

## 📂 Estrutura do Repositório

* [`installation.md`](./installation.md): Guia passo a passo completo para provisionamento do ambiente com KVM2, Libvirt, CNI Flannel, Pixie CLI, deploy da Google Online Boutique e execução dos scripts PxL com as respectivas saídas esperadas. Inclui também o protocolo de injeção de falhas (Passo 10), o painel de falhas (Passo 11) e as limitações observadas (Passo 12).
* `imgs/`: Capturas de tela das execuções no terminal, grafos de serviço e tabelas extraídas da interface web do Pixie.
* `scripts/falhas.sh`: Script de injeção e reversão de falhas (rede, aplicação, CPU/memória, disponibilidade e carga). Registra cada ação com data e hora em `resultados/experimentos.csv`. Uso: `./scripts/falhas.sh ajuda`.
* `scripts/dashboard_falhas.pxl`: Painel PxL de falhas com ranking de risco por rota, série temporal de p99/erros, últimos erros, fluxo L4 serviço → serviço e tráfego por pod.
* `scripts/diag_http.pxl` e `scripts/diag_proc.pxl`: Scripts de diagnóstico da coleta do Pixie (protocolos decodificados e métricas de processo).
* `resultados/`: Saídas dos experimentos (JSON do painel, `kubectl top` e o registro `experimentos.csv`).
