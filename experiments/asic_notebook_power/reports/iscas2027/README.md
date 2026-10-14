# Experimentos SAURIA usados no paper ISCAS 2027

Este guia liga os resultados SAURIA do paper aos perfis, manifests e scripts
deste repositório. O paper e seus arquivos gerados ficam no checkout irmão
`../iscas2027` (no ambiente de desenvolvimento, `/home/tarsio/gaph/iscas2027`).

## Caminho rápido para reproduzir os artefatos publicados

Os reports ASIC e as contagens SRAM usados no paper já estão versionados neste
repositório. Para conferir o dataset do paper sem instalar Torch, SciPy ou EDA,
na raiz do SAURIA execute:

```bash
python3 experiments/asic_notebook_power/common/generate_vectors.py \
  --profile int16_3x3 --case conv-x3-y3 \
  --out /tmp/sauria-iscas2027-vectors --paper-dataset-only
```

O comando gera os tensores e o golden em `normal_dataset/`, compara os hashes
do IFMAP e dos pesos e verifica o checksum FNV-1a de saída `015f2e08`. Ele
precisa apenas de Python 3 e NumPy. Para recriar também os arquivos `.mem` e
simular o SAURIA, use o ambiente Python completo descrito em
`Python/requirements_pip.txt` e os fluxos `make flow` abaixo.

Para regenerar a tabela ASIC e os artefatos LaTeX completos do paper, são
necessários também os checkouts irmãos de `iscas2027`, `FastConv_SystemVerilog`
e `WinoCNN`, com os reports de campanhas indicados nesses projetos. Com os três
checkouts disponíveis ao lado do SAURIA:

```bash
SAURIA_DIR="$PWD" \
FASTCONV_DIR="$(realpath ../FastConv_SystemVerilog)" \
WINOCNN_DIR="$(realpath ../WinoCNN)" \
  python3 ../iscas2027/scripts/gen_tables.py --check

WINOCNN_DIR="$(realpath ../WinoCNN)" \
  python3 ../iscas2027/scripts/gen_memory.py
make -C ../iscas2027 build
```

`gen_tables.py` também escreve os CSV/TeX/figuras gerados antes de conferir as
regras de comparação com `--check`; por isso rode-o em uma cópia limpa do
checkout do paper ou revise o diff depois. Sem os outros projetos, os valores
SAURIA continuam consultáveis nos JSON/CSV versionados neste repositório, mas
não é possível reconstruir a tabela comparativa inteira só a partir dele.

## Resultados ASIC do paper

O paper usa três arrays. Os JSONs abaixo são a fonte local dos valores e da
proveniência completa; os CSVs são consolidados para consulta e geração das
tabelas.

| Rótulo no paper | Perfil e lanes usados | Report de origem | Commit RTL/flow | Ciclos / tempo | Área standard-cell | Potência / energia estimada |
| --- | --- | --- | --- | ---: | ---: | ---: |
| SAURIA, 9 MACs | [`int16_3x3`](../../int16_3x3/), `3×3` | [`int16_ppa_energy_20261009.json`](../int16_ppa_energy_20261009.json) | `6bdb5b0` | 44.044 / 88,088 µs | 35.793,702 µm² | 10,7567 mW / 947,5 nJ |
| SAURIA, 20 MACs | [`int16_4x5`](../../int16_4x5/), `4×5` | [`int16_ppa_energy_retile4x5_20261009.json`](../int16_ppa_energy_retile4x5_20261009.json) | `a1431f6` (síntese); modelo gate corrigido em `636c69a` | 28.066 / 56,132 µs | 50.212,134 µm² | 15,9439 mW / 895,0 nJ |
| SAURIA, 36 MACs | [`int16_6x6`](../../int16_6x6/), `6×6` | [`int16_ppa_energy_retile6x6_20261009.json`](../int16_ppa_energy_retile6x6_20261009.json) | `0f3f66c` | 21.658 / 43,316 µs | 64.613,178 µm² | 19,8278 mW / 858,9 nJ |

Os três usam o workload `IFMAP=3×32×32`, `weights=12×3×3×3`,
`OFMAP=12×30×30`, operandos e acumulador signed de 16 bits, kernel 3×3,
stride 1, padding 0. Os manifests registram a mesma entrada de dados
(`seed=20261004`, normal(0,1), escala `2^8`, truncamento para zero e wrap
signed), os mesmos SHA-256 de IFMAP e pesos e o checksum de saída `015f2e08`.

Os relatórios usam 500 MHz, `DRAM_BANDWIDTH=128` bits/ciclo e timing scope
`accelerator_internal`. A área e potência reportadas excluem as macros SRAM não
caracterizadas. Os WNS de corner lento são muito próximos de zero; leia as
notas de cada JSON antes de chamar esses resultados de fechamento robusto de
timing. A energia por camada é estimada como potência vezes ciclos vezes o
período de 2 ns.

## Contagens de acesso à SRAM usadas no paper

O paper combina os números ASIC acima com contagens de acessos por banco A/B/C
em [`sram_access_counts_ce13ea3_20261010.csv`](../sram_access_counts_ce13ea3_20261010.csv).
Esse arquivo registra as variantes 3×3, 4×5 e 6×6, Verilator 5.052 e o resultado
`NOTEBOOK_LAYER_PASS`. A cópia consumida pelo gerador do paper está em
`../iscas2027/data/sauria-access.csv`.

Essas contagens alimentam uma estimativa separada de energia de memória; não são
medidas de potência Joules das SRAMs. O fluxo ASIC trata as SRAMs como black
boxes sem macro caracterizada, portanto a energia e área de SRAM ficam fora da
tabela PPA de core.

## Regenerar as tabelas do paper

Com o checkout `iscas2027` ao lado deste repositório, regenere as tabelas a
partir dos relatórios já versionados, sem executar Genus/Xcelium/Joules:

```bash
cd ../iscas2027
SAURIA_DIR="$(cd ../sauria && pwd)" python3 scripts/gen_tables.py --check
python3 scripts/gen_memory.py
make build
```

`gen_tables.py` escolhe os relatórios `retile` para os pontos 4×5 e 6×6 e o
relatório de campanha `int16_ppa_energy_20261009` para 3×3. Ele atualiza
`data/asic.csv`, tabelas/figuras derivadas e valida as comparações com `--check`.
`gen_memory.py` atualiza `tab/memory-energy.tex` usando
`data/sauria-access.csv`. Os relatórios JSON neste repositório preservam os
run IDs, checksums, versões EDA, resultados e commits usados para os valores
publicados.

## Refazer o fluxo ASIC

O `make flow` executa RTL sim → Genus → gate-level sim com SDF → Joules e grava
os artefatos associados ao novo `RUN_ID`. No checkout atual, os perfis ativos
são:

```bash
make flow PROFILE=int16_3x3 RUN_ID=<id-novo-3x3>
make flow PROFILE=int16_4x5 RUN_ID=<id-novo-4x5>
make flow PROFILE=int16_6x6 RUN_ID=<id-novo-6x6>
```

Execute cada campanha sequencialmente em `tmux` na Paxos, no checkout
`/sim/tarsio.onofrio/sauria`, com as versões de ferramentas indicadas nos manifests.
O Makefile verifica host, raiz Git e `tmux`; use um `RUN_ID` novo para cada
execução. Os resultados ficam nos diretórios `run_metadata/<RUN_ID>/`,
`logical/results/<RUN_ID>/`, `sim/run_artifacts/<RUN_ID>/` e
`power/results/<RUN_ID>/` dentro do perfil.

O gerador atual na branch `iscas2027` usa a seed `20261004` registrada nos
manifests e reproduz os hashes SHA-256 de IFMAP e pesos do workload publicado.
Isso permite reconstruir os mesmos tensores; ainda assim, um rerun só reproduz
os números de PPA se também usar o snapshot RTL, defines, scripts e modelo gate
correspondentes a cada linha (em especial o modelo gate indicado para 4×5).
Confira os hashes dos tensores e o checksum da simulação antes de comparar PPA.
Qualquer diferença deve ser registrada como um novo experimento, sem substituir
os reports históricos. As campanhas de contagem SRAM (`--count-only`) são
workloads separados e mantêm seed `0`.

Os snapshots completos para refazer as campanhas são:

| Perfil | Snapshot para rerun completo | Observação |
| --- | --- | --- |
| `int16_3x3` | `6bdb5b019feabb01ace7dc0a3d5e63c6e4fe815c` | fonte registrada no report 3×3 |
| `int16_4x5` | `636c69a11c0d5958943dc90959fe2d2618517982` | contém a configuração de síntese de `a1431f6` e o modelo SRAM corrigido usado na simulação gate-level |
| `int16_6x6` | `0f3f66c1dafe80701eaee6f8e505e770e6c9c483` | fonte registrada no report 6×6 |

Para cada ponto, deixe limpos e no mesmo commit os checkouts local e da Paxos,
salve o branch/commit atual, e selecione o snapshot correspondente nos dois
checkouts. Na Paxos, dentro de `tmux`, rode o `make flow` do perfil com um
`RUN_ID` novo. Depois dos três pontos, restaure o branch/commit salvo nos dois
checkouts e confirme que voltaram ao mesmo SHA. O `RUN_ID` novo preserva os
artefatos históricos e permite comparar os hashes da entrada e do golden com
os JSONs desta tabela.

## Arquivos do paper

No checkout irmão `iscas2027`:

- `data/asic.csv`: valores de tempo, área, potência e energia usados na tabela;
- `tab/asic-results.tex`: tabela ASIC incluída em `main.tex`;
- `data/sauria-access.csv`: contagens SAURIA usadas na estimativa de memória;
- `tab/memory-energy.tex`: energia de core mais estimativa de memória;
- `scripts/gen_tables.py` e `scripts/gen_memory.py`: geradores dessas tabelas.

Para entender os demais projetos e os mapeamentos de todos os rótulos do paper,
consulte também o guia `report/iscas2027/README.md` do repositório FastConv.
