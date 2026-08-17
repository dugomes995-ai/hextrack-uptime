# hextrack-uptime

Checagem externa de disponibilidade do HexTrack.

## Por que este repo existe

O HexTrack tem um watchdog rodando dentro da própria VPS. Ele cobre o caso "a VPS está
viva mas a aplicação caiu", que foi o incidente de 04/08/2026. Ele **não** cobre a VPS
inteira morrer: nesse cenário ninguém roda o cron e o silêncio é total.

Este repo roda a checagem na infra do GitHub, de fora da Hostinger. Sobrevive à VPS sumir.

## Como funciona

A cada 10 minutos, **três runners independentes** sondam os mesmos três endpoints públicos
(`/health`, `/login` e um redirect de campanha). Cada job do Actions roda numa VM própria,
com IP próprio, e é isso que dá o sinal: um runner sozinho falhando é problema de rede
daquele IP, não do HexTrack.

Duas barreiras antes de virar e-mail:

1. **Quórum.** Precisa de 2 dos 3 runners falhando na mesma rodada.
2. **Rodadas seguidas.** Precisa do quórum falhar em 2 rodadas consecutivas.

Resultado por rodada:

| Estado | O que significa | Manda e-mail? |
|---|---|---|
| `ok` | todos alcançaram | não (fecha alerta aberto) |
| `ruido` | 1 runner falhou, sem quórum | não, só registra no STATUS.md |
| `suspeita` | quórum falhou, 1ª rodada | não, aguarda a próxima |
| `fora` | quórum falhou em 2 rodadas | **sim**, abre issue |
| `indefinido` | menos de 2 runners responderam | não (falha da infra do Actions) |

Não duplica alerta: se já existe issue aberta, não abre outra. **Voltou** → comenta e fecha
a issue sozinho.

### Por que não bastava repetir a sonda

O desenho antigo já tentava 3 vezes antes de alertar, mas as 3 tentativas saíam do **mesmo
runner**, ou seja, do mesmo IP. Contra bloqueio de borda isso não serve de nada: as tentativas
falham todas juntas.

Entre 05 e 09/08/2026 saíram **17 alertas com o serviço no ar**. No alerta de 09/08 16:27, o
log do backend mostrava tráfego real de cliente entrando sem interrupção durante toda a janela
(4 requisições por minuto, nenhum minuto vazio). A borda da Hostinger bloqueia IPs de forma
intermitente, e o mesmo já acontece com o IP fixo do escritório.

### Regra de decisão

Fica em [`scripts/decidir.sh`](scripts/decidir.sh), separada do workflow para poder ser
testada sem rede e sem GitHub:

```bash
scripts/test-decidir.sh
```

O teste cobre os dois casos que importam: o falso positivo (1 runner isolado falhando, 5
rodadas seguidas, nunca alerta) e a queda real (quórum em 2 rodadas, alerta).

### Ao receber um alerta

Confirmar antes de tratar como queda. Com SSH: `docker ps` na VPS e o log do backend mostram
na hora se há tráfego de cliente entrando. Serviço no ar com sonda externa falhando já
aconteceu e vai acontecer de novo.

## Por que é público e por que não tem segredo

Repo público tem minuto de Actions ilimitado, então a checagem não consome a cota do repo
privado do produto. E o alerta sai por issue justamente para **não precisar de credencial
nenhuma** aqui dentro. Só existem URLs que já são públicas.

## STATUS.md

Registro do que aconteceu. Quando está tudo certo, uma linha por dia. Quando uma rodada dá
`ruido`, `suspeita` ou `indefinido`, entra uma linha ali **sem** virar e-mail: o padrão fica
visível para quem for procurar, sem gastar a atenção de quem não está procurando.

Serve também para manter o agendamento vivo (o GitHub desativa workflow agendado em repo sem
atividade por 60 dias).

## state/falhas-consecutivas

Contador de rodadas seguidas com quórum de falha. Zera assim que uma rodada volta a alcançar
o serviço. É o que impede uma falha isolada de escalar para alerta.
