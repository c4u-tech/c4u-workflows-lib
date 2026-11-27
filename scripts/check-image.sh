#!/usr/bin/env bash
# Confere o usuário declarado numa imagem: tem de ser um número, e não pode ser zero.
# Uso: check-image.sh "<usuário>", com o que
#   docker inspect --format '{{.Config.User}}' <imagem>
# devolve. Aceita "65532" e "65532:65532". Recusa vazio (a imagem roda como root),
# zero, e nome ("nonroot"): por nome, quem lê o manifesto não tem como saber que o
# processo não é root.
set -euo pipefail

user="${1-}"
if [[ "$user" =~ ^[1-9][0-9]*(:[0-9]+)?$ ]]; then
  exit 0
fi
echo "check-image.sh: o usuário da imagem é '${user}'; tem de ser um número diferente de zero (USER 65532:65532)" >&2
exit 1
