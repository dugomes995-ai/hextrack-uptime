#!/usr/bin/env bash
# Smoke test da lógica de decisão. Roda sem rede e sem GitHub.
# Uso: scripts/test-decidir.sh

set -uo pipefail

aqui="$(cd "$(dirname "$0")" && pwd)"
decidir="$aqui/decidir.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

falhou=0

# monta <n> vereditos, os <k> primeiros como fora
montar() {
  local dir="$1" n="$2" k="$3" i
  rm -rf "$dir"; mkdir -p "$dir"
  for i in $(seq 1 "$n"); do
    mkdir -p "$dir/veredito-$i"
    if [ "$i" -le "$k" ]; then
      printf 'estado=fora\nfalha: https://api.hextrack.com.br/health respondeu 000 (esperado 200)\n' \
        > "$dir/veredito-$i/veredito.txt"
    else
      printf 'estado=ok\n' > "$dir/veredito-$i/veredito.txt"
    fi
  done
}

checar() {
  local nome="$1" esperado="$2" obtido="$3"
  if [ "$obtido" = "$esperado" ]; then
    echo "  ok   $nome"
  else
    echo "  FALHOU $nome: esperado '$esperado', obtido '$obtido'"
    falhou=1
  fi
}

estado_de() { grep -m1 '^estado=' <<< "$1" | cut -d= -f2; }
campo() { grep -m1 "^$2=" <<< "$1" | cut -d= -f2; }

echo "Teste da decisão de uptime"

# 1. Tudo respondendo
montar "$tmp/v" 3 0; echo 0 > "$tmp/estado"
out="$(bash "$decidir" "$tmp/v" "$tmp/estado")"
checar "3 runners ok -> ok" "ok" "$(estado_de "$out")"

# 2. Um runner só falhando = bloqueio de IP, NAO alerta
montar "$tmp/v" 3 1; echo 0 > "$tmp/estado"
out="$(bash "$decidir" "$tmp/v" "$tmp/estado")"
checar "1 de 3 fora -> ruido (sem alerta)" "ruido" "$(estado_de "$out")"
checar "  contador zerado" "0" "$(campo "$out" consecutivas)"

# 3. Quorum na 1a rodada = suspeita, ainda nao alerta
montar "$tmp/v" 3 2; echo 0 > "$tmp/estado"
out="$(bash "$decidir" "$tmp/v" "$tmp/estado")"
checar "2 de 3 fora, 1a rodada -> suspeita" "suspeita" "$(estado_de "$out")"
checar "  contador em 1" "1" "$(campo "$out" consecutivas)"

# 4. Quorum na 2a rodada consecutiva = alerta de verdade
out="$(bash "$decidir" "$tmp/v" "$tmp/estado")"
checar "2 de 3 fora, 2a rodada -> fora" "fora" "$(estado_de "$out")"
checar "  contador em 2" "2" "$(campo "$out" consecutivas)"

# 5. Voltou: contador zera
montar "$tmp/v" 3 0
out="$(bash "$decidir" "$tmp/v" "$tmp/estado")"
checar "voltou -> ok" "ok" "$(estado_de "$out")"
checar "  contador zerado" "0" "$(campo "$out" consecutivas)"

# 6. Falha isolada NAO acumula rumo ao alerta (o caso dos 17 falsos positivos)
echo 0 > "$tmp/estado"
for _ in 1 2 3 4 5; do
  montar "$tmp/v" 3 1
  out="$(bash "$decidir" "$tmp/v" "$tmp/estado")"
done
checar "5 rodadas com 1 runner fora -> nunca alerta" "ruido" "$(estado_de "$out")"
checar "  contador nunca subiu" "0" "$(campo "$out" consecutivas)"

# 7. Todos fora em 2 rodadas = queda real, alerta
echo 0 > "$tmp/estado"
montar "$tmp/v" 3 3
out="$(bash "$decidir" "$tmp/v" "$tmp/estado")"
checar "3 de 3 fora, 1a rodada -> suspeita" "suspeita" "$(estado_de "$out")"
out="$(bash "$decidir" "$tmp/v" "$tmp/estado")"
checar "3 de 3 fora, 2a rodada -> fora" "fora" "$(estado_de "$out")"

# 8. Infra do Actions falhou (poucos vereditos): nao decide, preserva contador
montar "$tmp/v" 1 1; echo 1 > "$tmp/estado"
out="$(bash "$decidir" "$tmp/v" "$tmp/estado")"
checar "1 runner só -> indefinido" "indefinido" "$(estado_de "$out")"
checar "  contador preservado" "1" "$(campo "$out" consecutivas)"
checar "  arquivo intacto" "1" "$(cat "$tmp/estado")"

# 9. Alerta carrega as sondas que falharam
montar "$tmp/v" 3 2; echo 1 > "$tmp/estado"
out="$(bash "$decidir" "$tmp/v" "$tmp/estado")"
if grep -q 'api.hextrack.com.br/health' <<< "$out"; then
  echo "  ok   alerta lista as sondas que falharam"
else
  echo "  FALHOU alerta sem detalhe das sondas"; falhou=1
fi

# 10. Estado ausente na primeira execucao nao quebra
rm -f "$tmp/estado"; montar "$tmp/v" 3 0
out="$(bash "$decidir" "$tmp/v" "$tmp/estado")"
checar "sem arquivo de estado -> ok" "ok" "$(estado_de "$out")"

echo
if [ "$falhou" -eq 0 ]; then
  echo "TODOS OS TESTES PASSARAM"
else
  echo "TESTES FALHARAM"
fi
exit "$falhou"
