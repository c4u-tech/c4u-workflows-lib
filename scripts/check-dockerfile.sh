#!/usr/bin/env bash
# Confere que toda imagem que um Dockerfile traz de um registro vem por digest
# (@sha256:). Uma imagem entra por quatro lugares, e os quatro são conferidos: FROM,
# COPY --from, RUN --mount com from, e a linha `# syntax=`, que troca o próprio
# leitor do Dockerfile.
# Uso: check-dockerfile.sh <Dockerfile>
# Sai com 0 se todas vêm, com 1 se alguma não vem, com 2 se o arquivo não existe.
#
# Aceita, sem digest, só o que não é imagem de registro: `scratch`, o nome de um
# estágio anterior e, em --from, o número de um estágio. Uma imagem dada por
# argumento (FROM ${BASE}) é recusada: o digest tem de estar escrito no arquivo,
# onde a revisão e o Dependabot o enxergam.
#
# As linhas são lidas como o Docker as lê: as terminadas no caractere de escape são
# juntadas à seguinte, e os comentários saem. O corpo de um heredoc não é
# reconhecido: uma linha dele que comece com FROM é conferida como instrução, e o
# erro é para o lado da recusa.
set -euo pipefail

file="${1:?uso: check-dockerfile.sh <Dockerfile>}"
if [ ! -f "$file" ]; then
  echo "check-dockerfile.sh: não existe o arquivo $file" >&2
  exit 2
fi

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
pinned() { [[ "$1" =~ @sha256:[0-9a-f]{64}$ ]]; }

stages=" "
bad=0

# Uma origem de COPY --from ou de RUN --mount: estágio, número de estágio, ou imagem
# por digest.
check_source() {
  local source="$1" where="$2"
  [[ "$source" =~ ^[0-9]+$ ]] && return 0
  case "$stages" in *" $(lower "$source") "*) return 0 ;; esac
  if ! pinned "$source"; then
    echo "imagem sem digest em $where: ${source:-(vazia)}"
    bad=1
  fi
}

check_line() {
  local keyword rest image name word part
  read -r keyword rest <<<"$1"
  # shellcheck disable=SC2086  # a linha é quebrada em palavras de propósito
  set -f && set -- $rest && set +f
  case "$(lower "$keyword")" in
    from)
      while [ "$#" -gt 0 ] && [ "${1#--}" != "$1" ]; do shift; done
      image="${1:-}"
      name=""
      if [ "$#" -ge 3 ] && [ "$(lower "$2")" = "as" ]; then name="$(lower "$3")"; fi
      case "$stages" in
        *" $(lower "$image") "*) ;;
        *)
          if [ "$image" != "scratch" ] && ! pinned "$image"; then
            echo "imagem de base sem digest: ${image:-(vazia)}"
            bad=1
          fi
          ;;
      esac
      if [ -n "$name" ]; then stages="$stages$name "; fi
      ;;
    copy | add)
      for word in "$@"; do
        case "$word" in --from=*) check_source "${word#--from=}" "COPY --from" ;; esac
      done
      ;;
    run)
      for word in "$@"; do
        case "$word" in
          --mount=*)
            while IFS= read -r part; do
              case "$part" in from=*) check_source "${part#from=}" "RUN --mount" ;; esac
            done < <(printf '%s\n' "${word#--mount=}" | tr ',' '\n')
            ;;
        esac
      done
      ;;
  esac
}

# As diretivas do leitor só valem no topo, antes de qualquer outra linha.
escape="\\"
top=true
logical=""
while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" =~ ^[[:space:]]*# ]]; then
    if [ "$top" = true ] && [[ "$line" =~ ^[[:space:]]*#[[:space:]]*([A-Za-z]+)[[:space:]]*=[[:space:]]*([^[:space:]]+) ]]; then
      # Guardados antes de outro teste de padrão, que apagaria o resultado deste.
      directive="$(lower "${BASH_REMATCH[1]}")"
      value="${BASH_REMATCH[2]}"
      case "$directive" in
        syntax)
          if ! pinned "$value"; then
            echo "linha syntax sem digest: $value"
            bad=1
          fi
          ;;
        escape) escape="$value" ;;
      esac
    else
      top=false
    fi
    # Um comentário no meio de uma instrução continuada sai, e a instrução segue.
    continue
  fi
  [[ "$line" =~ ^[[:space:]]*$ ]] && [ -z "$logical" ] && continue
  top=false
  trimmed="${line%"${line##*[![:space:]]}"}"
  if [ -n "$trimmed" ] && [ "${trimmed: -1}" = "$escape" ]; then
    logical="$logical${trimmed%?}"
    continue
  fi
  check_line "$logical$line"
  logical=""
done < <(tr -d '\r' <"$file")
if [ -n "$logical" ]; then check_line "$logical"; fi

if [ "$bad" -ne 0 ]; then
  echo "check-dockerfile.sh: toda imagem tem de vir por digest, como nome:marca@sha256:..." >&2
  exit 1
fi
