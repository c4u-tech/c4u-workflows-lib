# c4u-workflows-lib

Instruções para agentes de IA e para quem contribui.

## O que este repositório é

Workflows reutilizáveis, chamados por outros repositórios com `uses:`. É público, e
tudo o que está aqui roda dentro do job de quem chama, com as permissões dele.

## O que nunca entra aqui

- Segredo, chave ou token, nem em exemplo.
- Detalhe de operação: nome de máquina, endereço de rede, nome de cluster, ambiente
  além de `stg` e `prd`, e qualquer regra de implantação ou de revert. O repositório
  de estado é entrada de quem chama; as regras dele moram nele.
- Ação de terceiros. Só `actions/checkout` e `actions/create-github-app-token`, as
  duas fixadas por commit com a versão no comentário.
- Binário baixado sem soma conferida.

## Regras de escrita

- Nenhuma entrada de workflow é interpolada num comando (`${{ inputs.x }}` dentro de
  `run:`). Toda entrada chega por `env:` e é conferida por expressão regular antes
  do uso.
- Token nunca vai em argumento de comando nem é impresso.
- Comportamento novo ou mudado entra com o teste em `tests/run.sh`, no mesmo commit.
- Mudança de entrada ou de saída do `build-image.yml` é mudança de contrato: versão
  maior, e o README junto.
- Identificadores em inglês, prosa em português.

## Como testar

`tests/run.sh` e `shellcheck scripts/*.sh tests/run.sh`, os dois com código zero.
