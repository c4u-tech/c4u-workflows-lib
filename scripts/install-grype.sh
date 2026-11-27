#!/usr/bin/env bash
# Baixa o grype numa versão fixada, confere a soma e põe o binário em <destino>/grype.
# Uso: install-grype.sh <destino>
# Sai com 1 se a soma não confere, e com 2 se o runner não é linux/amd64.
# A soma é a do arquivo grype_<versão>_checksums.txt da publicação. Trocar a versão é
# trocar as duas linhas abaixo, num PR.
set -euo pipefail

version=0.122.1
sha256=f1ba7e2917ee1395618de20a98da0aa7c0fb1788927797651047c50502a37538

dest="${1:?uso: install-grype.sh <destino>}"

# O pacote e a soma fixados são os de linux/amd64. Noutra arquitetura o binário
# passaria na soma e falharia ao rodar: recusa aqui, com o motivo.
machine="$(uname -m)"
case "$machine" in
  x86_64 | amd64) ;;
  *)
    echo "install-grype.sh: só há pacote fixado para amd64, e este runner é $machine" >&2
    exit 2
    ;;
esac
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

archive="grype_${version}_linux_amd64.tar.gz"
curl -fsSL -o "$work/$archive" "https://github.com/anchore/grype/releases/download/v${version}/${archive}"

if command -v sha256sum >/dev/null 2>&1; then
  got="$(sha256sum "$work/$archive" | cut -d ' ' -f 1)"
else
  got="$(shasum -a 256 "$work/$archive" | cut -d ' ' -f 1)"
fi
if [ "$got" != "$sha256" ]; then
  echo "install-grype.sh: a soma de $archive não confere (esperada $sha256, veio $got)" >&2
  exit 1
fi

mkdir -p "$dest"
tar -xzf "$work/$archive" -C "$dest" grype
