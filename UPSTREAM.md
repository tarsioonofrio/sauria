# Relação com o upstream SAURIA

Este fork é usado para experimentos de ASIC e alterações associadas ao SAURIA.
O upstream do projeto é <https://github.com/bsc-loca/sauria>.

## Estado da comparação

Comparação registrada em 2026-10-13:

- upstream `main`: `2bb469e4e4ab7413b88c985b4c83a98b9544c827`
- ancestral comum com este fork: o mesmo commit acima
- commits deste fork depois da base: 171
- commits do upstream depois da base: 0
- `origin` local aponta para o fork `tarsioonofrio/sauria`; ainda não há remote
  `upstream` configurado neste checkout.

O fork mantém a estrutura original (`RTL/`, `Python/`, `test/`, `tools/` e
submódulos) e acrescenta principalmente o fluxo em
`experiments/asic_notebook_power/`. Também há mudanças em arquivos centrais de
`RTL/`, `Python/` e `test/verilator/`; portanto, nem todo o trabalho derivado
está isolado na pasta `experiments/`.

## Regra de organização

- Preservar caminhos, nomes e interfaces do código original sempre que
  possível. Não copiar RTL original para dentro de experimentos.
- Manter wrappers, configurações ASIC, geração de vetores, campanhas e relatórios
  em `experiments/asic_notebook_power/`.
- Alterações necessárias em `RTL/`, `Python/` ou `test/` devem ser pequenas,
  justificadas e registradas em commits focados. Não misturar refatoração de
  organização com correção funcional ou mudança de arquitetura.
- Manter saídas regeneráveis de ferramentas fora do Git; versionar configurações
  e relatórios duráveis necessários para reproduzir ou interpretar campanhas.
- Preservar o histórico atual de `main`. Não fazer reset, rebase ou force-push
  para tentar converter retroativamente os 171 commits em uma série limpa.

## Sincronização futura

Antes de integrar atualizações do upstream, buscar e comparar os históricos:

```bash
git remote add upstream https://github.com/bsc-loca/sauria.git
git fetch upstream --tags
git merge-base main upstream/main
git log --oneline --left-right main...upstream/main
```

O comando `remote add` deve ser executado somente se `upstream` ainda não
existir. Depois da comparação, integrar `upstream/main` em uma branch de
trabalho e validar RTL, notebooks/testes afetados e submódulos antes de atualizar
o branch compartilhado. Não usar `reset --hard` nem force-push para sincronizar.

Para contribuir uma alteração de volta ao SAURIA, criar uma branch nova a partir
de `upstream/main` e reaplicar somente os commits necessários, em vez de abrir
um PR com todo o histórico experimental do fork. O `main` atual continua sendo
o estado de pesquisa do fork.

## Atualização deste registro

Os hashes e a contagem acima são um retrato da comparação de 2026-10-13. Atualize
esta seção depois de buscar o upstream novamente; não trate esses números como
estado permanente.
