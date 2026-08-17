#!/usr/bin/env bash
# Decide se o HexTrack está mesmo fora do ar a partir dos vereditos dos runners.
#
# Existe porque a sondagem de um runner só não é confiável: a borda da Hostinger
# bloqueia IPs de forma intermitente, e o runner bloqueado vê 000 em tudo mesmo com
# o serviço no ar e clientes usando. Foram 17 alertas falsos em 5 dias (05 a 09/08/2026).
#
# Duas barreiras contra falso positivo:
#   1. QUORUM entre runners distintos (VMs com IPs diferentes). Um runner isolado
#      falhando é bloqueio de IP, não queda.
#   2. RODADAS CONSECUTIVAS. Só alerta se o quórum falhar em rodadas seguidas.
#      Pode ser conservador porque o watchdog DENTRO da VPS é quem detecta rápido;
#      este aqui cobre o caso "VPS inteira sumiu", que não se resolve sozinho em 10min.
#
# Uso: decidir.sh <dir-vereditos> <arquivo-estado> [limiar-consecutivas]
# Escreve estado=ok|ruido|suspeita|fora em stdout no formato chave=valor.

set -euo pipefail

dir_vereditos="${1:?dir de vereditos}"
arquivo_estado="${2:?arquivo de estado}"
limiar="${3:-2}"

total=0
fora=0
falhas_texto=""

for v in "$dir_vereditos"/*/veredito.txt "$dir_vereditos"/veredito*.txt; do
  [ -f "$v" ] || continue
  total=$((total + 1))
  if grep -q '^estado=fora$' "$v"; then
    fora=$((fora + 1))
    falhas_texto+="$(sed -n 's/^falha: //p' "$v")"$'\n'
  fi
done

anterior=0
[ -f "$arquivo_estado" ] && anterior="$(tr -cd '0-9' < "$arquivo_estado")"
[ -n "$anterior" ] || anterior=0

# Menos de 2 runners responderam: problema na infra do Actions, não do HexTrack.
# Não decide nada e preserva o contador para a próxima rodada.
if [ "$total" -lt 2 ]; then
  echo "estado=indefinido"
  echo "runners_total=$total"
  echo "runners_fora=$fora"
  echo "consecutivas=$anterior"
  exit 0
fi

quorum=$((total / 2 + 1))

if [ "$fora" -ge "$quorum" ]; then
  consecutivas=$((anterior + 1))
  if [ "$consecutivas" -ge "$limiar" ]; then
    estado=fora
  else
    estado=suspeita
  fi
else
  consecutivas=0
  if [ "$fora" -gt 0 ]; then
    estado=ruido
  else
    estado=ok
  fi
fi

mkdir -p "$(dirname "$arquivo_estado")"
printf '%s\n' "$consecutivas" > "$arquivo_estado"

echo "estado=$estado"
echo "runners_total=$total"
echo "runners_fora=$fora"
echo "quorum=$quorum"
echo "consecutivas=$consecutivas"

if [ -n "${falhas_texto//[$'\n']/}" ]; then
  echo 'falhas<<FIMFALHAS'
  printf '%s' "$falhas_texto" | sort -u | sed '/^$/d'
  echo 'FIMFALHAS'
fi
