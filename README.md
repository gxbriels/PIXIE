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
* **Google Online Boutique (`microservices-demo`):** Aplicação alvo do estudo. Trata-se de um e-commerce completo composto por **11 microsserviços** poliglotas (Go, C#, Node.js, Python, Java) que se comunicam intensivamente via **gRPC** e **HTTP REST**, além de um gerador de tráfego sintético (`loadgenerator`) e persistência em cache (`redis-cart`).

---

## 🔬 Metodologia de Análise de Rede

A coleta de dados e a avaliação experimental dividem-se em quatro eixos fundamentais:

1. **Topologia e Grafo de Dependências (Camada L7):** Mapeamento visual do fluxo de entrada (`frontend`) e das chamadas internas entre os microsserviços (`cartservice`, `checkoutservice`, `paymentservice`, `currencyservice`, etc.), medindo a taxa de requisições por segundo (RPS) e os percentis de latência.
2. **Matriz de Comunicação HTTP/gRPC:** Auditoria granular por rota (`GET /`, `GET /product/*`, `POST /cart`, `POST /cart/checkout`) e checagens de saúde do Kubelet (`GET /_healthz`), contrastando o tempo de resposta de operações de leitura em cache versus transações distribuídas síncronas.
3. **Telemetria de Transporte e Vazão (Camada L4):** Monitoramento do volume bruto de bytes recebidos (`RX`) e transmitidos (`TX`) por pod através da tabela `network_stats`, auditando a integridade da pilha virtual de rede por meio da contagem de pacotes descartados ou com erro (`rx_errors` / `tx_errors`).
4. **Descoberta de Serviços e Resolução DNS:** Rastreamento das consultas ao **CoreDNS** (`kube-dns`) para avaliar a latência de *Service Discovery* em microssegundos e o comportamento de encaminhamento para o gateway upstream do KVM.


---

## 📂 Estrutura do Repositório

* [`installation.md`](./installation.md): Guia passo a passo completo para provisionamento do ambiente com KVM2, Libvirt, CNI Flannel, Pixie CLI, deploy da Google Online Boutique e execução dos scripts PxL com as respectivas saídas esperadas.
* `imgs/`: Capturas de tela das execuções no terminal, grafos de serviço e tabelas extraídas da interface web do Pixie.
