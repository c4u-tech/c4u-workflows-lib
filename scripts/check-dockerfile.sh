#!/usr/bin/env bash
# Confere que toda imagem de base de um Dockerfile vem por digest (@sha256:).
# Uso: check-dockerfile.sh <Dockerfile>
# Sai com 0 se todas vêm, com 1 se alguma não vem, com 2 se o arquivo não existe.
#
# Aceita, sem digest, só o que não é imagem de registro: `scratch` e o nome de um
# estágio anterior. Uma base dada por argumento (FROM ${BASE}) é recusada: o digest
# tem de estar escrito no arquivo, onde a revisão e o Dependabot o enxergam.
set -euo pipefail

file="${1:?uso: check-dockerfile.sh <Dockerfile>}"
if [ ! -f "$file" ]; then
  echo "check-dockerfile.sh: não existe o arquivo $file" >&2
  exit 2
fi

stages=" "
bad=0
while read -r keyword rest; do
  [ "$(printf '%s' "$keyword" | tr '[:upper:]' '[:lower:]')" = "from" ] || continue
  # shellcheck disable=SC2086  # a linha é quebrada em palavras de propósito
  set -- $rest
  while [ "$#" -gt 0 ] && [ "${1#--}" != "$1" ]; do shift; done
  image="${1:-}"
  name=""
  if [ "$#" -ge 3 ] && [ "$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')" = "as" ]; then
    name="$3"
  fi
  case "$stages" in
    *" $image "*) ;;
    *)
      if [ "$image" != "scratch" ] && ! [[ "$image" =~ @sha256:[0-9a-f]{64}$ ]]; then
        echo "imagem de base sem digest: ${image:-(vazia)}"
        bad=1
      fi
      ;;
  esac
  [ -n "$name" ] && stages="$stages$name "
done < <(tr -d '\r' <"$file")

if [ "$bad" -ne 0 ]; then
  echo "check-dockerfile.sh: toda imagem de base tem de vir por digest, como nome:marca@sha256:..." >&2
  exit 1
fi
