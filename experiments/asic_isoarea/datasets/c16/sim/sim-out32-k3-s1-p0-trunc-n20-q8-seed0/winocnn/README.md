# WinoCNN dataset

Gerado pela lib `fast-convolution-rtl`.

| arquivo | conteudo |
|---|---|
| `feature.bin` | int8, `Cin*H*W`, layout `c*H*W + h*W + w` |
| `weight.bin` | int8, `Cout*Cin*kh*kw`, layout `(od*Cin+id)*kh*kw + ks` |
| `params.json` | descritor da convolucao (dims, stride, pad, scale) |

Como alimentar o WinoCNN:

```
# 1) empacotar no layout DDR e validar contra o golden do WinoCNN
testbench/single_main ... file:<dir>/feature.bin ... file:<dir>/weight.bin ...
# 2) gerar o estimulo RTL
python3 asic_scripts/bin2hex.py <dir>
```
