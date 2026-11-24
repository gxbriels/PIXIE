#!/usr/bin/env bash
# =============================================================================
# falhas.sh — Injeção controlada de falhas na Google Online Boutique
#             (Minikube kvm2 + Flannel + Pixie)
#
# Uso:  ./falhas.sh <comando> [args]
#       ./falhas.sh ajuda
#
# Toda ação é registrada em experimentos.csv (horário local + fuso), para
# depois cruzar com as janelas de tempo das consultas no Pixie.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS="${NS:-boutique}"
LOG="${LOG:-$SCRIPT_DIR/../resultados/experimentos.csv}"
mkdir -p "$(dirname "$LOG")"
MANIFEST_URL="https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml"
# Se existir uma cópia local do manifesto em scripts/ (recomendado: versão fixa e replicável), usa ela.
MANIFEST_LOCAL="$SCRIPT_DIR/kubernetes-manifests.yaml"
MANIFEST="${MANIFEST:-$( [[ -f "$MANIFEST_LOCAL" ]] && echo "$MANIFEST_LOCAL" || echo "$MANIFEST_URL" )}"

# Reservas (requests) reduzidas: necessárias numa VM de 4 GB, senão pods ficam Pending
REQ_CPU="${REQ_CPU:-20m}"
REQ_MEM="${REQ_MEM:-32Mi}"

IMG_NET="nicolaka/netshoot"      # contém tc / iproute2
IMG_STRESS="alexeiled/stress-ng" # entrypoint = stress-ng

# ----------------------------------------------------------------------------- utilitários
log() { # log <evento> <alvo> <detalhe>
  [[ -f "$LOG" ]] || echo "timestamp,evento,alvo,detalhe" > "$LOG"
  echo "$(date +%Y-%m-%dT%H:%M:%S%z),$1,$2,\"$3\"" >> "$LOG"
  echo ">> [$(date +%H:%M:%S)] $1 | $2 | $3"
}

pod_de() { # primeiro pod Running do app
  kubectl get pod -n "$NS" -l app="$1" --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}'
}

tc_no_pod() { # tc_no_pod <servico> <args do tc...>
  # Cria um container efêmero que compartilha o namespace de rede do pod alvo e
  # executa o comando tc nele. A regra fica na interface eth0 do pod até ser
  # removida ou até o pod ser recriado.
  # Os pods da Boutique rodam como não-root (runAsUser 1000); o container efêmero
  # herdaria esse usuário e o tc falharia com "RTNETLINK: Operation not permitted".
  # Por isso usamos um perfil customizado que força root + NET_ADMIN.
  local svc="$1"; shift
  local pod; pod="$(pod_de "$svc")"
  [[ -n "$pod" ]] || { echo "Pod do serviço '$svc' não encontrado"; exit 1; }
  local perfil; perfil="$(mktemp --suffix=.json)"
  cat > "$perfil" <<'EOF'
{"securityContext":{"runAsUser":0,"runAsNonRoot":false,"capabilities":{"add":["NET_ADMIN"]}}}
EOF
  local saida
  saida="$(kubectl debug -n "$NS" "$pod" -c "chaos-$(date +%s)" \
    --image="$IMG_NET" --profile=general --custom="$perfil" --attach=true -- \
    sh -c "tc $* && echo TC_OK; echo '--- qdisc atual em eth0:'; tc qdisc show dev eth0" 2>&1)" || true
  rm -f "$perfil"
  echo "$saida"
  grep -q TC_OK <<<"$saida" || { echo "!! tc FALHOU — nada foi aplicado nem registrado"; exit 1; }
}

ajustar_recursos() { # reduz os requests de todos os deployments (não mexe nos limits)
  kubectl set resources deployment --all -n "$NS" --requests=cpu="$REQ_CPU",memory="$REQ_MEM" >/dev/null
}

# ----------------------------------------------------------------------------- comandos
cmd_marco() { # marca uma fase do experimento (baseline / recuperacao / etc.)
  log "MARCO" "-" "${1:-baseline}"
}

# ---------- REDE (L3/L4) ----------
cmd_latencia() { # latencia <svc> <atraso> [jitter]
  local svc="$1" atraso="${2:-300ms}" jitter="${3:-50ms}"
  tc_no_pod "$svc" qdisc replace dev eth0 root netem delay "$atraso" "$jitter"
  log "REDE_LATENCIA" "$svc" "delay $atraso jitter $jitter (egress eth0)"
}

cmd_perda() { # perda <svc> <percentual>
  local svc="$1" pct="${2:-20%}"
  tc_no_pod "$svc" qdisc replace dev eth0 root netem loss "$pct"
  log "REDE_PERDA" "$svc" "loss $pct (egress eth0)"
}

cmd_rede_reset() { # rede-reset <svc>
  local svc="$1"
  tc_no_pod "$svc" "qdisc del dev eth0 root 2>/dev/null; true"
  log "REDE_RESET" "$svc" "qdisc netem removida"
}

# ---------- APLICAÇÃO ----------
cmd_catalogo_lento() { # catalogo-lento <duracao>  (recurso nativo da Boutique)
  local d="${1:-500ms}"
  kubectl set env deployment/productcatalogservice -n "$NS" EXTRA_LATENCY="$d"
  log "APP_LATENCIA" "productcatalogservice" "EXTRA_LATENCY=$d"
}

# ---------- INFRA (CPU / memória) ----------
cmd_cpu_stress() { # cpu-stress <workers> <segundos>   (vizinho barulhento no nó)
  local w="${1:-4}" t="${2:-300}"
  kubectl run "stress-cpu-$(date +%s)" -n "$NS" --image="$IMG_STRESS" \
    --restart=Never --labels=chaos=stress -- \
    --cpu "$w" --cpu-load 100 --timeout "${t}s" --metrics-brief
  log "INFRA_CPU_STRESS" "no (todos)" "stress-ng --cpu $w por ${t}s"
}

cmd_mem_stress() { # mem-stress <MB> <segundos>  (cuidado: VM de 4 GB)
  local mb="${1:-1024}" t="${2:-300}"
  kubectl run "stress-mem-$(date +%s)" -n "$NS" --image="$IMG_STRESS" \
    --restart=Never --labels=chaos=stress -- \
    --vm 1 --vm-bytes "${mb}M" --vm-keep --timeout "${t}s" --metrics-brief
  log "INFRA_MEM_STRESS" "no (todos)" "stress-ng --vm-bytes ${mb}M por ${t}s"
}

cmd_cpu_limite() { # cpu-limite <svc> <millicores>  (throttling de CPU no serviço)
  local svc="$1" m="${2:-20}"
  kubectl set resources deployment/"$svc" -n "$NS" \
    --requests=cpu="${m}m" --limits=cpu="${m}m"
  kubectl rollout status deployment/"$svc" -n "$NS" --timeout=120s || true
  log "INFRA_CPU_LIMITE" "$svc" "cpu limit=${m}m"
}

cmd_mem_limite() { # mem-limite <svc> <Mi>  (força OOMKilled / CrashLoop)
  local svc="$1" mi="${2:-32}"
  kubectl set resources deployment/"$svc" -n "$NS" \
    --requests=memory="${mi}Mi" --limits=memory="${mi}Mi"
  log "INFRA_MEM_LIMITE" "$svc" "memory limit=${mi}Mi"
}

# ---------- DISPONIBILIDADE ----------
cmd_derrubar() { # derrubar <svc>
  kubectl scale deployment/"$1" -n "$NS" --replicas=0
  log "DISP_DERRUBAR" "$1" "replicas=0"
}

cmd_restaurar() { # restaurar <svc>
  kubectl scale deployment/"$1" -n "$NS" --replicas=1
  log "DISP_RESTAURAR" "$1" "replicas=1"
}

cmd_matar_pods() { # matar-pods <svc> <vezes> <intervalo_s>  (chaos monkey)
  local svc="$1" n="${2:-5}" i="${3:-30}"
  log "DISP_MATAR_PODS_INICIO" "$svc" "$n vezes a cada ${i}s"
  for k in $(seq 1 "$n"); do
    kubectl delete pod -n "$NS" -l app="$svc" --wait=false
    echo "   pod de $svc removido ($k/$n)"; sleep "$i"
  done
  log "DISP_MATAR_PODS_FIM" "$svc" "-"
}

# ---------- DEMANDA ----------
cmd_carga() { # carga <usuarios> [taxa_spawn] [replicas]
  local u="${1:-100}" r="${2:-10}" rep="${3:-1}"
  kubectl set env deployment/loadgenerator -n "$NS" USERS="$u" RATE="$r"
  kubectl scale deployment/loadgenerator -n "$NS" --replicas="$rep"
  log "CARGA" "loadgenerator" "USERS=$u RATE=$r replicas=$rep"
}

# ---------- VOLTAR AO NORMAL ----------
cmd_reset() { # reset [svc ...]
  # Sem argumentos: remove stress, EXTRA_LATENCY, e reaplica o manifesto (réplicas,
  # limites, env do loadgenerator) SEM reiniciar tudo de uma vez — reiniciar os 12
  # deployments juntos numa VM de 4 GB deixa a loja indisponível por minutos.
  # Com argumentos: reinicia também os serviços listados (necessário para descartar
  # regras netem ou limites de CPU/memória aplicados neles).
  kubectl delete pod -n "$NS" -l chaos=stress --ignore-not-found
  kubectl set env deployment/productcatalogservice -n "$NS" EXTRA_LATENCY- 2>/dev/null || true
  kubectl apply -n "$NS" -f "$MANIFEST" >/dev/null
  ajustar_recursos   # o apply devolve os requests ao padrão; reduz de novo
  for svc in "$@"; do
    kubectl rollout restart deployment/"$svc" -n "$NS"
    kubectl rollout status  deployment/"$svc" -n "$NS" --timeout=180s || true
  done
  log "RESET" "${*:-geral}" "manifesto reaplicado ($MANIFEST)"
}

cmd_recursos() { # aplica os requests reduzidos (uso após implantar a Boutique)
  ajustar_recursos
  log "RECURSOS" "todos" "requests cpu=$REQ_CPU memory=$REQ_MEM"
}

cmd_status() {
  kubectl get pods -n "$NS" -o wide
  echo; kubectl get deploy -n "$NS" \
    -o custom-columns='NOME:.metadata.name,REPLICAS:.spec.replicas,CPU_LIM:.spec.template.spec.containers[0].resources.limits.cpu,MEM_LIM:.spec.template.spec.containers[0].resources.limits.memory'
}

cmd_ajuda() {
  cat <<EOF
Comandos:
  marco <nome>                         marca fase (baseline, falha, recuperacao)
  latencia <svc> [atraso] [jitter]     atraso de rede no pod (tc netem)
  perda <svc> [pct]                    perda de pacotes no pod (tc netem)
  rede-reset <svc>                     remove a regra netem do pod
  catalogo-lento [duracao]             EXTRA_LATENCY no productcatalogservice
  cpu-stress [workers] [seg]           stress-ng de CPU no nó (vizinho barulhento)
  mem-stress [MB] [seg]                stress-ng de memória no nó
  cpu-limite <svc> [millicores]        throttling de CPU no serviço
  mem-limite <svc> [Mi]                limite de memória baixo (OOMKilled)
  derrubar <svc> / restaurar <svc>     réplicas 0 / 1
  matar-pods <svc> [vezes] [interv_s]  apaga o pod repetidamente
  carga [usuarios] [taxa] [replicas]   aumenta a demanda do loadgenerator
  reset [svc ...]                      volta ao estado original (reinicia só os svc listados)
  recursos                             reduz os requests (obrigatório em VM de 4 GB)
  status                               pods, réplicas e limites atuais

Registro das ações: $LOG

Exemplos:
  ./falhas.sh marco baseline
  ./falhas.sh latencia currencyservice 300ms 50ms
  ./falhas.sh rede-reset currencyservice
  ./falhas.sh derrubar paymentservice
  ./falhas.sh carga 150 15 2
  ./falhas.sh reset currencyservice
EOF
}

# ----------------------------------------------------------------------------- despacho
c="${1:-ajuda}"; shift || true
fn="cmd_${c//-/_}"
if declare -F "$fn" >/dev/null; then "$fn" "$@"; else echo "Comando desconhecido: $c"; cmd_ajuda; exit 1; fi
