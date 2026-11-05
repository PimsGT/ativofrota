# Plano — AtivoFrota

## Objetivo
Transformar a planilha `Controle de Máquinas e Frotas 2025.xlsm` em uma ferramenta acessível de gestão patrimonial, com leitura executiva, inventário pesquisável, acompanhamento de auditoria e relatórios gerenciais.

## Escopo implementado
- Dashboard executivo com 497 ativos, composição por categoria e saúde de auditoria.
- Inventário com busca, filtros por categoria/status, cadastro de novo ativo e persistência local.
- Auditoria com fila de pendências, índice de conformidade e trilha de eventos.
- Relatórios gerenciais com exportação CSV.
- Estrutura pronta para sincronização futura com Firebase Authentication, Firestore e Storage.
- Estrutura pronta para versionamento e colaboração via GitHub.

## Fonte de dados
A planilha contém 12 abas. A aba EQUIPAMENTOS foi usada para consolidar os indicadores iniciais: 497 ativos classificados, com maior concentração em TRATOR (81), PLATAFORMA (78), COLHETADEIRA (54), PLANTADEIRA (54), PULVERIZADOR (41) e DISTRIBUIDOR (29).

## Arquitetura
- `index.html`: shell da aplicação e views.
- `src/styles.css`: identidade visual responsiva.
- `src/app.js`: estado local, navegação, filtros, relatórios e auditoria.
- `firebase-config.example.js`: deve ser criado na próxima etapa para credenciais do projeto Firebase; nunca commitar credenciais administrativas.
- `README.md`: instalação, GitHub e Firebase.

## Design
**Estilos candidatos:** editorial industrial silencioso (0,06); dashboard SaaS verde-azulado (0,88); maximalismo documental (0,04). Escolhido: dashboard SaaS verde-azulado.

**Movimento:** uma sala de controle patrimonial serena, com verde profundo, superfícies claras e sinais de auditoria que comunicam confiança sem parecer um ERP pesado.

**Princípios:** hierarquia executiva; densidade informacional com respiro; estados de auditoria explícitos; ações rápidas e reversíveis.

**Paleta:** verde profundo para confiança e patrimônio; menta para evidência positiva; âmbar e vermelho apenas para exceções; fundo quase branco para leitura prolongada.

**Layout:** sidebar fixa para navegação operacional; hero editorial assimétrico para contexto; painéis com tabelas e barras para leitura de cima para baixo.

**Assinaturas:** marca AF em bloco menta; anéis de saúde da auditoria; etiquetas de status com semântica consistente.

**Tipografia:** sistema sans-serif com títulos compactos e etiquetas em caixa alta com espaçamento de letras.

**Voz:** objetiva, calma e orientada à ação. Exemplos: “Controle que dá visibilidade ao patrimônio.” e “O que merece revisão aparece primeiro.”

## Integração planejada
O app foi mantido sem dependências para funcionar imediatamente no Windows. A conexão real com Firebase requer o projeto e as credenciais Web do usuário; o README descreve o caminho seguro para adicionar isso depois, sem expor chaves administrativas no frontend.


## Gestão multiempresa
A operação passa a considerar três empresas: AGRO IPUÃ, SANTA MARIA e SERRA BRANCA. Cada ativo possui empresa proprietária, além do local operacional. O seletor global permite enxergar uma empresa isoladamente, os cartões do dashboard mostram a distribuição da base e o inventário pode ser filtrado por empresa.

Transferências são registradas por ativo, empresa de origem, empresa de destino, motivo, data e usuário. A movimentação atualiza a empresa proprietária do ativo e aparece na atividade recente e na trilha de auditoria. No Firebase, essa operação deve ser persistida em `transfers` e também gerar um evento imutável em `auditLogs`.
