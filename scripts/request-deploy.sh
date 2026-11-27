#!/usr/bin/env bash
# Pede a implantação de um digest ao repositório de estado, e acompanha a execução.
# Uso: request-deploy.sh <repositório de estado> <serviço> <ambiente> <digest> \
#        <revisão de origem> <esperar: true|false>
# Dispara o workflow deploy.yml no ramo main do repositório de estado. Com esperar,
# acompanha a execução disparada e sai com 0 se ela termina em success, com 1 se
# termina de outro jeito, e com 3 se não termina no prazo. Sai com 2 se um argumento
# é recusado, antes de qualquer pedido.
#
# Precisa de GH_TOKEN, com permissão de disparar workflow no repositório de estado. O
# token nunca é impresso e vai ao curl por descritor de arquivo, e não por argumento:
# argumento aparece na lista de processos do runner.
set -euo pipefail

[ "$#" -eq 6 ] || { echo "uso: request-deploy.sh <repositório> <serviço> <ambiente> <digest> <revisão> <true|false>" >&2; exit 2; }
repo="$1" service="$2" environment="$3" digest="$4" revision="$5" wait="$6"

refuse() {
  echo "request-deploy.sh: $1" >&2
  exit 2
}
# Os valores entram num corpo JSON: só passam os que não têm como quebrá-lo.
[[ "$repo" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*/[A-Za-z0-9_][A-Za-z0-9._-]*$ ]] || refuse "repositório de estado inválido"
[[ "$service" =~ ^[a-z][a-z0-9-]{0,30}$ ]] || refuse "nome de serviço inválido"
[[ "$environment" =~ ^(stg|prd)$ ]] || refuse "ambiente inválido: só stg e prd"
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || refuse "digest inválido: sha256 e 64 dígitos hexadecimais"
[[ "$revision" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+@[0-9a-f]{40}$ ]] || refuse "revisão de origem inválida: <dono>/<repositório>@<commit>"
[[ "$wait" =~ ^(true|false)$ ]] || refuse "esperar é true ou false"

api="${GITHUB_API_URL:-https://api.github.com}"
deadline="${REQUEST_DEPLOY_DEADLINE_SECONDS:-2400}"
poll="${REQUEST_DEPLOY_POLL_SECONDS:-10}"

call() {
  curl -fsS \
    -H @<(printf 'Authorization: Bearer %s' "${GH_TOKEN:?request-deploy.sh: falta GH_TOKEN}") \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    "$@"
}

# Lê um campo de primeiro nível de um JSON na entrada; vazio se não existe ou é nulo.
field() {
  node -e '
    let data = {};
    try { data = JSON.parse(require("fs").readFileSync(0, "utf8")); } catch (error) {}
    const value = data[process.argv[1]];
    if (value !== undefined && value !== null) console.log(String(value));
  ' "$1"
}

note() {
  echo "$1"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then echo "$1" >>"$GITHUB_STEP_SUMMARY"; fi
}

body="$(printf '{"ref":"main","return_run_details":true,"inputs":{"service":"%s","env":"%s","digest":"%s","source_revision":"%s"}}' \
  "$service" "$environment" "$digest" "$revision")"
response="$(call -X POST -d "$body" "$api/repos/$repo/actions/workflows/deploy.yml/dispatches")"
run_id="$(field workflow_run_id <<<"$response")"
if ! [[ "$run_id" =~ ^[0-9]+$ ]]; then
  echo "request-deploy.sh: o pedido foi aceito, mas a resposta não trouxe a execução" >&2
  exit 1
fi
url="${GITHUB_SERVER_URL:-https://github.com}/$repo/actions/runs/$run_id"
note "Implantação pedida: $url"

[ "$wait" = true ] || exit 0

elapsed=0
while [ "$elapsed" -lt "$deadline" ]; do
  run="$(call "$api/repos/$repo/actions/runs/$run_id" 2>/dev/null || true)"
  if [ "$(field status <<<"$run")" = completed ]; then
    conclusion="$(field conclusion <<<"$run")"
    if [ "$conclusion" = success ]; then
      note "Implantação concluída: $service em $environment."
      exit 0
    fi
    note "A implantação terminou em ${conclusion:-(sem resultado)}: $url"
    exit 1
  fi
  sleep "$poll"
  elapsed=$((elapsed + poll))
done
note "A implantação não terminou em $deadline segundos: $url"
exit 3
