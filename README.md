# c4u-workflows-lib

Workflows reutilizáveis do GitHub Actions. Hoje há um: `build-image.yml`, que constrói
a imagem de um serviço, confere, publica por digest e pede a implantação a um
repositório de estado.

## O que o `build-image.yml` faz

| Passo | O que faz |
| :--- | :--- |
| Conferir o Dockerfile | Toda imagem de base vem por digest (`@sha256:`) |
| Construir | `docker build`, com os argumentos de quem chama. O commit de origem é gravado na etiqueta `org.opencontainers.image.revision` pelo workflow: o Dockerfile não precisa colaborar |
| Conferir a imagem | O usuário declarado é um número, e não é zero |
| Varrer | Vulnerabilidades conhecidas, com o grype baixado por soma fixada. Falha em vulnerabilidade crítica que já tem correção |
| Publicar | `docker push`, e a leitura do digest |
| Pedir | Dispara o workflow `deploy.yml` no ramo `main` do repositório de estado, com o token de um aplicativo do GitHub |
| Esperar | Acompanha a execução disparada e termina com o resultado dela |

## O que ele recusa

- Imagem de base sem digest, inclusive a que vem por argumento (`FROM ${BASE}`).
- Imagem sem `USER`, com `USER 0` ou com usuário por nome (`USER nonroot`).
- Vulnerabilidade crítica com correção publicada.
- Entrada fora do formato: nome de imagem, marca, argumento de construção, serviço,
  ambiente e repositório de estado são conferidos antes de qualquer uso.

## Como um produto chama

```yaml
name: image

on:
  push:
    branches: [stg]

jobs:
  api:
    permissions:
      contents: read
      packages: write
      id-token: write
    uses: c4u-tech/c4u-workflows-lib/.github/workflows/build-image.yml@<commit> # v1.0.0
    with:
      context: services/api
      image: ghcr.io/<dono>/<produto>-api
      tag: ${{ github.sha }}
      service: <produto>-api
      state_repository: <dono>/<repositório de estado>
      deploy_request_app_client_id: ${{ vars.DEPLOY_REQUEST_APP_CLIENT_ID }}
    secrets:
      deploy_request_app_private_key: ${{ secrets.DEPLOY_REQUEST_APP_PRIVATE_KEY }}
```

Um job por serviço. A chamada é fixada por commit, com a versão no comentário, e o
Dependabot do produto (ecossistema `github-actions`) abre o PR quando sai versão nova.

### Ramos

A implantação em staging acontece em push no ramo `stg` do produto, e só nele: é o
`on:` de quem chama que garante isso. Um PR, inclusive de fork, não recebe o segredo
do aplicativo e não deve chamar este workflow com `push` ligado. A produção não passa
por aqui: é promoção por PR no repositório de estado.

### Entradas

| Entrada | Padrão | O que é |
| :--- | :--- | :--- |
| `context` | `.` | Diretório de contexto da construção |
| `dockerfile` | `<context>/Dockerfile` | Caminho do Dockerfile |
| `image` | obrigatória | Nome da imagem, com o registro e sem marca |
| `tag` | obrigatória | Marca publicada. A implantação usa o digest |
| `build_args` | vazio | Argumentos de construção, um `NOME=valor` por linha |
| `service` | vazio | Nome do serviço no repositório de estado |
| `env` | `stg` | Ambiente da implantação |
| `state_repository` | vazio | Repositório de estado, como `<dono>/<nome>` |
| `runner` | `ubuntu-latest` | Um rótulo, ou uma lista JSON de rótulos, como `'["self-hosted", "x"]'` |
| `push` | `true` | Desligado, só constrói e confere |
| `deploy` | `true` | Pedir a implantação depois de publicar |
| `wait` | `true` | Esperar a implantação e terminar com o resultado dela |
| `deploy_request_app_client_id` | vazio | Client ID do aplicativo que pede a implantação |

Segredo: `deploy_request_app_private_key`, a chave privada do mesmo aplicativo.
Saída: `digest`.

O registro é o primeiro trecho de `image`, e o login usa o token do próprio job. Na
prática isso é o `ghcr.io`, com `packages: write` no job que chama.

### O aplicativo que pede a implantação

Um aplicativo do GitHub com uma permissão só, Actions com leitura e escrita, instalado
só no repositório de estado. O token que o workflow emite com ele é restrito a esse
repositório e a essa permissão: dispara workflow, e não lê nem escreve conteúdo.

### O que o runner precisa ter

`docker`, `git`, `curl`, `node`, `tar` e `sha256sum`. Os runners do GitHub têm todos.

## Desenvolver

```bash
tests/run.sh
```

```bash
shellcheck scripts/*.sh tests/run.sh
```

Os testes não usam Docker nem rede. A CI roda os dois e mais o `build-image.yml`
inteiro sobre `tests/dockerfiles/good`, sem publicar.

Uma versão nova é uma etiqueta `vX.Y.Z` sobre um commit do `main`.

## Licença

MIT. Ver [LICENSE](LICENSE).
