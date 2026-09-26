# Observabilidade e Profiling de Infraestrutura com eBPF

## 📌 Propósito do Projeto
Este repositório contém os estudos, protótipos e documentações desenvolvidos para a disciplina de Laboratório de Pesquisa I e II do bacharelado em Sistemas de Informação no IFES Campus Serra. O objetivo central é explorar a programabilidade em nível de sistema operacional e realizar a avaliação de desempenho (*profiling*) de uma arquitetura baseada em microsserviços. 

Em vez de focar estritamente no tráfego da camada de rede, este projeto utiliza instrumentação avançada para atuar como um "raio-X" da infraestrutura. A meta é mapear o consumo de CPU, alocação de memória RAM e chamadas de sistema (*syscalls*) de cada nó e contêiner em tempo real, estabelecendo uma linha de base (*baseline*) comportamental capaz de expor gargalos de processamento e anomalias de segurança.

## 🧠 Entendendo a Tecnologia

*   **eBPF (Extended Berkeley Packet Filter):** É o motor tecnológico da pesquisa. O eBPF permite executar programas em um ambiente estritamente isolado e seguro (*sandbox*) diretamente dentro do núcleo do Linux (*Kernel Space*). Isso possibilita interceptar eventos de infraestrutura com eficiência máxima e sem sobrecarga (overhead), eliminando a necessidade de modificar o código-fonte do kernel ou inserir *logs* manualmente nas aplicações alvo.
*   **Pixie:** A plataforma analítica *Cloud-Native*. O Pixie implanta microssensores no cluster que utilizam o eBPF para coletar a telemetria bruta. Ele processa esses dados, permitindo a execução de consultas e extração de gráficos dinâmicos (como *Flamegraphs*) para auditar a saúde e o peso da infraestrutura.
*   **Kubernetes (Minikube):** O orquestrador responsável pelo gerenciamento automatizado dos contêineres de teste. O ambiente utiliza uma topologia local para garantir um laboratório (sandbox) controlado.
*   **Sock Shop (Aplicação Alvo):** Uma loja virtual de demonstração arquitetada em múltiplos serviços (banco de dados, carrinho, catálogo). Ela é utilizada para gerar tráfegoHTTP real e consumo de processamento, servindo como o "sujeito de testes" para o perfilamento do eBPF.

## 🎯 Situação Geral e Próximos Passos

A topologia de observabilidade já se encontra provisionada e validada, operando com injeção de código *Just-In-Time* diretamente nas funções do kernel. O laboratório atual foca em:

*   **Continuous Profiling:** Identificar quais funções e microsserviços específicos estão exigindo maior carga de processamento dos nós.
*   **Geração de Baseline:** Documentar o consumo padrão do sistema em estado saudável.
*   **Tracing de Infraestrutura:** Analisar tempos de resposta de disco e rede para embasar avaliações estruturadas de desempenho.
