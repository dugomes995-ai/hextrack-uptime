# hextrack-uptime

Checagem externa de disponibilidade do HexTrack.

## Por que este repo existe

O HexTrack tem um watchdog rodando dentro da própria VPS. Ele cobre o caso "a VPS está
viva mas a aplicação caiu", que foi o incidente de 04/08/2026. Ele **não** cobre a VPS
inteira morrer: nesse cenário ninguém roda o cron e o silêncio é total.

Este repo roda a checagem na infra do GitHub, de fora da Hostinger. Sobrevive à VPS sumir.

## Como funciona

A cada 10 minutos, sonda três endpoints públicos (`/health`, `/login` e um redirect de
campanha). Cada sonda tenta 3 vezes antes de contar como falha, para blip de rede não
virar alarme.

- **Caiu** → abre uma issue com a label `uptime-down`. O GitHub notifica o dono por e-mail.
- **Voltou** → comenta e fecha a issue sozinho.

Não duplica alerta: se já existe issue aberta, não abre outra.

## Por que é público e por que não tem segredo

Repo público tem minuto de Actions ilimitado, então a checagem não consome a cota do repo
privado do produto. E o alerta sai por issue justamente para **não precisar de credencial
nenhuma** aqui dentro. Só existem URLs que já são públicas.

## STATUS.md

Registro de heartbeat, um por dia. Serve para duas coisas: histórico simples e manter o
agendamento vivo (o GitHub desativa workflow agendado em repo sem atividade por 60 dias).
