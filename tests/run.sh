#!/usr/bin/env bash
# Testes dos scripts, sem Docker e sem rede: o curl e o sleep são de mentira, postos
# na frente no PATH. Todos os casos rodam; o script falha se algum falhar.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
failures=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

digest=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
revision=example-org/example@0123456789abcdef0123456789abcdef01234567

mkdir -p "$tmp/bin"

# curl de mentira, com três papéis, pelo endereço pedido:
#   .../dispatches        -> guarda os argumentos em $FIXTURES/dispatch-args e devolve
#                            o arquivo $FIXTURES/dispatch
#   .../actions/runs/<id> -> devolve a primeira linha de $FIXTURES/runs e a tira da
#                            fila; a última linha se repete para sempre
#   qualquer outro, com -o -> é o download: copia $FIXTURES/download para o destino
cat >"$tmp/bin/curl" <<'MOCK'
#!/usr/bin/env bash
out=""
prev=""
for arg in "$@"; do
  [ "$prev" = "-o" ] && out="$arg"
  prev="$arg"
done
url="$prev"
case "$url" in
  */dispatches)
    printf '%s\n' "$@" >"$FIXTURES/dispatch-args"
    cat "$FIXTURES/dispatch"
    ;;
  */actions/runs/*)
    head -n 1 "$FIXTURES/runs"
    if [ "$(wc -l <"$FIXTURES/runs")" -gt 1 ]; then
      tail -n +2 "$FIXTURES/runs" >"$FIXTURES/runs.next" && mv "$FIXTURES/runs.next" "$FIXTURES/runs"
    fi
    ;;
  *)
    cp "$FIXTURES/download" "$out"
    ;;
esac
MOCK
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$tmp/bin/sleep"
chmod +x "$tmp/bin/curl" "$tmp/bin/sleep"

expect() {
  local want="$1" title="$2" got
  shift 2
  PATH="$tmp/bin:$PATH" FIXTURES="$tmp/fixtures" GH_TOKEN=fake "$@" >"$tmp/log" 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then
    echo "ok: $title"
  else
    echo "FALHOU: $title (esperado $want, veio $got)"
    sed 's/^/    /' "$tmp/log"
    failures=$((failures + 1))
  fi
}

fixtures() {
  rm -rf "$tmp/fixtures"
  mkdir -p "$tmp/fixtures"
}

check_dockerfile="$root/scripts/check-dockerfile.sh"
check_image="$root/scripts/check-image.sh"
install_grype="$root/scripts/install-grype.sh"
request_deploy="$root/scripts/request-deploy.sh"

echo "== check-dockerfile"
expect 0 "todo FROM com digest" "$check_dockerfile" "$root/tests/dockerfiles/good/Dockerfile"
expect 1 "um FROM por etiqueta" "$check_dockerfile" "$root/tests/dockerfiles/by-tag/Dockerfile"
expect 0 "FROM de um estágio anterior, com --platform e em minúsculas" "$check_dockerfile" "$root/tests/dockerfiles/stage/Dockerfile"
expect 0 "FROM scratch" "$check_dockerfile" "$root/tests/dockerfiles/scratch/Dockerfile"
expect 1 "FROM por argumento" "$check_dockerfile" "$root/tests/dockerfiles/by-arg/Dockerfile"
expect 2 "arquivo que não existe" "$check_dockerfile" "$root/tests/dockerfiles/none/Dockerfile"

echo "== check-image"
expect 0 "usuário 65532:65532" "$check_image" "65532:65532"
expect 0 "usuário 1000" "$check_image" "1000"
expect 1 "usuário por nome" "$check_image" "nonroot"
expect 1 "usuário vazio" "$check_image" ""
expect 1 "usuário 0" "$check_image" "0"
expect 1 "usuário 0:0" "$check_image" "0:0"
expect 1 "usuário 00" "$check_image" "00"

echo "== install-grype"
fixtures
echo "não é o grype" >"$tmp/fixtures/download"
expect 1 "soma diferente da fixada" "$install_grype" "$tmp/grype"
if [ -e "$tmp/grype/grype" ]; then
  echo "FALHOU: o binário ficou no destino mesmo com a soma errada"
  failures=$((failures + 1))
fi

echo "== request-deploy"
run() { printf '{"id":42,"status":"%s","conclusion":%s,"html_url":"https://example.test/runs/42"}\n' "$1" "$2"; }

fixtures
echo '{"workflow_run_id":42,"run_url":"https://api.example.test/runs/42"}' >"$tmp/fixtures/dispatch"
{ run queued null; run in_progress null; run completed '"success"'; } >"$tmp/fixtures/runs"
expect 0 "pede e acompanha até success" "$request_deploy" example-org/state example stg "$digest" "$revision" true
body="$(cat "$tmp/fixtures/dispatch-args" 2>/dev/null)"
for piece in '"ref":"main"' '"return_run_details":true' '"service":"example"' '"env":"stg"' "\"digest\":\"$digest\"" "\"source_revision\":\"$revision\"" 'repos/example-org/state/actions/workflows/deploy.yml/dispatches'; do
  if ! grep -qF -- "$piece" <<<"$body"; then
    echo "FALHOU: o pedido não leva $piece"
    failures=$((failures + 1))
  fi
done
if grep -q fake "$tmp/log" || grep -q fake <<<"$body"; then
  echo "FALHOU: o token apareceu na saída ou nos argumentos do curl"
  failures=$((failures + 1))
fi

fixtures
echo '{"workflow_run_id":42}' >"$tmp/fixtures/dispatch"
run completed '"failure"' >"$tmp/fixtures/runs"
expect 1 "a execução termina em failure" "$request_deploy" example-org/state example stg "$digest" "$revision" true

fixtures
echo '{"workflow_run_id":42}' >"$tmp/fixtures/dispatch"
run completed '"cancelled"' >"$tmp/fixtures/runs"
expect 1 "a execução é cancelada" "$request_deploy" example-org/state example stg "$digest" "$revision" true

fixtures
echo '{"workflow_run_id":42}' >"$tmp/fixtures/dispatch"
run in_progress null >"$tmp/fixtures/runs"
expect 3 "a execução não termina até o prazo" env REQUEST_DEPLOY_DEADLINE_SECONDS=30 "$request_deploy" example-org/state example stg "$digest" "$revision" true

fixtures
echo '{}' >"$tmp/fixtures/dispatch"
expect 1 "resposta sem workflow_run_id" "$request_deploy" example-org/state example stg "$digest" "$revision" true

fixtures
echo '{"workflow_run_id":42}' >"$tmp/fixtures/dispatch"
run completed '"failure"' >"$tmp/fixtures/runs"
expect 0 "sem esperar, termina ao pedir" "$request_deploy" example-org/state example stg "$digest" "$revision" false

fixtures
expect 2 "recusa digest por etiqueta" "$request_deploy" example-org/state example stg v1 "$revision" true
expect 2 "recusa serviço com aspas" "$request_deploy" example-org/state 'a"b' stg "$digest" "$revision" true
expect 2 "recusa repositório com caminho" "$request_deploy" ../state example stg "$digest" "$revision" true
expect 2 "recusa ambiente desconhecido" "$request_deploy" example-org/state example dev "$digest" "$revision" true
expect 2 "recusa revisão sem commit" "$request_deploy" example-org/state example stg "$digest" example-org/example true
if [ -e "$tmp/fixtures/dispatch-args" ]; then
  echo "FALHOU: um pedido recusado chegou à API"
  failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
  echo "testes: $failures falha(s)"
  exit 1
fi
echo "testes: tudo certo"
