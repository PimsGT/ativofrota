# Relatório de auditoria técnica — AtivoFrota

**Data:** 25/11/2026  
**Escopo:** frontend, ordem de scripts, integrações Supabase/Firebase, persistência, documentos, auditoria, usuários, SQL/RLS, Storage, comandos locais e consistência do DOM.

## Veredito executivo

O projeto **não deve ser considerado validado para produção neste momento**. A sintaxe local está correta e a estrutura principal existe, mas foram encontrados problemas que podem causar histórico incorreto de transferências, funcionalidades órfãs e exposição indevida de documentos no Storage.

## Testes executados

- Varredura da estrutura do projeto, excluindo dependências vendorizadas.
- Leitura dos módulos ativos e dos módulos órfãos.
- Verificação de todos os scripts referenciados no `index.html`.
- `node --check` em **16 arquivos JavaScript**: passou.
- Conferência da ordem de carregamento dos scripts e dos eventos customizados.
- Conferência de seletores/IDs usados pelo código.
- Inspeção das migrações SQL, triggers, políticas RLS e funções `SECURITY DEFINER`.
- Inspeção da Edge Function `admin-create-user`.
- Verificação das regras Firebase e do `firebase.json`.
- Verificação da configuração pública do Supabase.
- Tentativa de teste HTTP pelo servidor local; o script inicia e imprime a URL, porém o listener não permaneceu acessível entre processos de teste automatizados, portanto o teste de rota HTTP ficou inconclusivo.
- Verificação de disponibilidade das ferramentas: Node e npm presentes; Supabase CLI e Firebase CLI não estão disponíveis no PATH.

## Achados críticos

### 1. Histórico de transferência pode ser registrado com tipo incorreto

A transferência no frontend atualiza simultaneamente `company_id`, `current_company_id` e `lifecycle_status = 'TRANSFERIDO'` em `src/supabase-persistence.js`. No trigger `record_asset_lifecycle_event()` de `asset-lifecycle-migration.sql`, a primeira condição testa mudança de `lifecycle_status` antes de testar mudança de empresa. Assim, uma transferência pode ser gravada como `RECLASSIFICACAO`, não como `TRANSFERENCIA`.

**Impacto:** histórico patrimonial incorreto e relatórios de movimentação inconsistentes.

**Correção recomendada:** no trigger, testar primeiro mudança de empresa (`current_company_id`/`company_id`) e registrar `TRANSFERENCIA`; só depois tratar venda, baixa ou demais mudanças de ciclo de vida. A atualização também deve ser transacional quando envolver ativo, evento e anexos.

### 2. Storage privado está protegido apenas no nível do bucket

Em `supabase/production-hardening.sql`, a política de leitura usa somente `bucket_id = 'ativos-documentos'`, e a política de inserção também aceita qualquer caminho nesse bucket para usuário autenticado. Isso permite que um usuário autenticado, se conhecer ou descobrir o caminho, leia ou grave arquivos de qualquer empresa/ativo.

**Impacto:** quebra da segregação patrimonial e possível acesso indevido a notas fiscais e fotos.

**Correção recomendada:** restringir `storage.objects` por caminho/ativo e empresa, ou centralizar upload/download em funções seguras que validem o vínculo do usuário com o ativo. Também validar MIME, tamanho e convenção de caminho no banco/Storage.

### 3. Funcionalidade de documentos pendentes está órfã

`src/pending-documents.js` existe e contém a fila de importação/vinculação de documentos, mas não é carregado pelo `index.html`. Além disso, os IDs que ele espera (`pendingFiles`, `pendingCompany`, `pendingAsset`, `pendingDocumentTable`, entre outros) não aparecem na interface publicada.

**Impacto:** essa rotina não pode funcionar no build atual; o código pode dar falsa impressão de que importação pendente está disponível.

**Correção recomendada:** ou remover o módulo órfão e sua documentação, ou incluir a tela/IDs e carregar o módulo explicitamente, com testes de upload, vinculação, retry e rollback.

### 4. Scripts e configurações Firebase legados coexistem com a arquitetura Supabase

O README declara que o Firebase é somente hosting, mas permanecem `firebase-init.js`, `firebase-config.js`, arquivos de exemplo e regras Firestore/Storage. Eles não são carregados no HTML atual, porém aumentam o risco de publicação/uso acidental e confundem a sequência operacional.

**Impacto:** manutenção ambígua, risco de executar regras/migrações do backend errado e possível divergência entre documentação e produção.

**Correção recomendada:** separar explicitamente `legacy/` ou remover os arquivos não utilizados; atualizar README e scripts de deploy para deixar Supabase como única fonte de dados.

### 5. Scripts de importação ainda usam o papel `admin`, incompatível com o modelo final

As migrações finais adotam apenas `master` e `patrimonial`, mas scripts de importação antigos ainda criam políticas condicionadas a `role = 'admin'`. Essas políticas podem ser substituídas posteriormente, mas a execução fora da ordem correta pode bloquear a carga ou deixar permissões incoerentes.

**Correção recomendada:** atualizar os scripts de importação para `master`, documentar a ordem única e eliminar políticas antigas ao final da carga.

## Achados importantes adicionais

- O frontend tem duas camadas de submit para `assetForm` e `transferForm`: `app.js` registra handlers locais e `supabase-persistence.js` intercepta em fase de captura com `stopImmediatePropagation()`. Atualmente a ordem tende a fazer a persistência Supabase prevalecer, mas o desenho é frágil e pode reintroduzir dupla gravação se a ordem dos scripts mudar.
- `supabase-ready` é disparado pelo módulo de inicialização antes de alguns módulos posteriores registrarem seus listeners. Há caminhos alternativos por `getSession()` e `ativofrota:authenticated`, mas a inicialização deveria ser centralizada para não depender de eventos perdidos.
- A Edge Function usa `Access-Control-Allow-Origin: *`. Para um painel corporativo, o ideal é restringir origens autorizadas, além de considerar limitação de tentativas e auditoria de criação de contas.
- A migração de ciclo de vida cria `asset_events` com leitura para qualquer usuário autenticado, enquanto a tela de monitor `audit_events` é exclusiva do Master. Deve ser confirmado se o histórico operacional deve ser visível a todos os perfis ou somente aos usuários autorizados.
- A captura inicial encontrou referências dinâmicas que não são problemas reais (`assetDocuments`, `reportLegend`, `reportTotal` aparecem no HTML), mas a checagem por regex simples não deve ser usada como único teste de DOM.
- Não existem testes automatizados de unidade, integração ou ponta a ponta no projeto.
- O repositório Git não está inicializado na raiz `Controle de Máquinas e Frotas`; o comando `git status` executado nessa raiz falhou. Isso dificulta rastrear correções e reverter migrações.

## O que passou

- Sintaxe JavaScript: 16/16 arquivos verificados sem erro pelo Node.
- Os 8 scripts referenciados pelo HTML existem.
- A configuração pública usa URL Supabase e chave publicável; não foi encontrada `service_role` na configuração frontend lida.
- O `index.html` possui gate de autenticação e o fluxo de sessão está conectado ao Supabase Auth.
- A Edge Function valida método, Bearer token, sessão, perfil Master, payload e faz rollback do usuário Auth se a criação do perfil falhar.
- As migrações possuem `IF NOT EXISTS`/`DROP POLICY IF EXISTS` em vários pontos e documentam uma ordem de execução.

## Sequência recomendada antes da liberação

1. Fazer backup/export do banco e criar/repositório Git para o estado atual.
2. Corrigir o trigger de transferência e criar teste SQL que confirme `TRANSFERENCIA` quando empresa muda.
3. Corrigir as políticas de `storage.objects` para autorização por ativo/empresa e testar usuário Master, Patrimonial autorizado e Patrimonial não autorizado.
4. Decidir o destino de `pending-documents.js` e das telas órfãs; não publicar funcionalidades parcialmente conectadas.
5. Consolidar os scripts SQL em uma sequência única, removendo a divergência `admin` versus `master`.
6. Aplicar as migrações em ambiente de homologação, não diretamente em produção.
7. Executar testes reais no Supabase com dois perfis e empresas distintas: login, troca de senha, leitura, cadastro, documento, foto, transferência, venda, baixa, auditoria e logout.
8. Instalar/autenticar Supabase CLI e Firebase CLI somente se o processo de deploy for realmente usado; validar `supabase db lint`/migrações e `firebase deploy --only hosting` em homologação.
9. Criar testes automatizados para os fluxos críticos e só então liberar a publicação.

## Conclusão

A base está funcional em nível de sintaxe e possui uma arquitetura Supabase coerente em grande parte do frontend, mas **a validação final falha por problemas de segurança do Storage, histórico de transferência e módulos órfãos**. Recomenda-se corrigir esses itens antes de qualquer declaração de pronto ou publicação para usuários operacionais.

## Atualização após início da sequência de correção

Foram aplicadas as seguintes correções:

- O trigger de `asset_events` agora verifica primeiro a mudança de empresa e registra `TRANSFERENCIA` antes de tratar alterações de ciclo de vida.
- As políticas do bucket `ativos-documentos` deixaram de ser bucket-wide. Foi criada a função `public.can_access_asset_storage(path)` para validar usuário ativo, Master ou vínculo do usuário com a empresa atual do ativo.
- As políticas de leitura e inserção do Storage passaram a usar essa autorização por caminho/ativo; o namespace `imports/` permanece permitido somente para usuários ativos.
- Os scripts `assets-import-setup.sql` e `assets-import-stage.sql` foram alinhados aos papéis `master` e `patrimonial`; não restaram políticas SQL ativas condicionadas a `role = 'admin'`.
- O README foi atualizado com a sequência operacional consolidada das migrações.

### Regressão após as correções

- JavaScript: **16/16 arquivos válidos**.
- Políticas SQL com `role = 'admin'`: **nenhuma encontrada**.
- Trigger: ramo de transferência confirmado antes do ramo de ciclo de vida.
- Storage: políticas bucket-wide antigas não encontradas; função de autorização usada nas políticas de leitura e inserção.
- Sequência documentada: todas as etapas críticas presentes e na ordem esperada.

Ainda falta aplicar as migrações em um projeto Supabase de homologação e executar testes reais com usuários Master e Patrimonial. A validação local não substitui esse teste contra o banco.

## Atualização — módulos órfãos tratados

Os módulos `unclassified-assets.js` e `pending-documents.js` foram conectados ao HTML de produção. Como a tela original não possuía os controles esperados, cada módulo agora cria explicitamente sua própria interface dentro de `pendenciasView`, sem depender de elementos inexistentes no HTML estático.

A interface de classificação inclui seleção do ativo, empresa de destino, observação e atualização de `company_id`, `current_company_id` e `classification_status`. A fila de documentos inclui seleção de empresa, vínculo opcional com ativo, tipo de documento, múltiplos arquivos, validação de tipo/tamanho, retry e envio sequencial.

A política de inserção de `asset_documents` também foi ajustada para aceitar `asset_id = null` somente quando o documento pendente pertence a uma empresa vinculada ao usuário; o Master continua podendo operar em todas as empresas.

Após a integração, foram confirmados: 16/16 arquivos JavaScript válidos, os dois módulos presentes no HTML, todos os IDs dinâmicos definidos pelos módulos, ordem de scripts preservada e política RLS para documentos pendentes presente. A validação visual e de interação no navegador ainda depende de um navegador conectado e de uma sessão Supabase real.


## Validação remota do Supabase

Em 25/11/2026, o projeto remoto `AtivoFrota Imobilizado` (`cryalcfhvoyyxijlorja`) foi autenticado e confirmado como vinculado ao diretório `app-imobilizado`.

- `supabase db lint --remote`: passou; os schemas `extensions` e `public` não apresentaram erros.
- `supabase functions list`: passou; `admin-create-user` está `ACTIVE`, versão 4.
- `supabase migration list --remote`: não retornou linhas; os estados Local e Remote estão vazios.

A ausência de linhas não prova que o banco remoto esteja vazio. Ela indica que os objetos podem ter sido criados pelo SQL Editor, dump ou outro processo sem histórico formal na tabela de migrações do Supabase. Por isso, os arquivos `supabase-user-access.sql`, `assets-rls-master-access.sql`, `asset-lifecycle-migration.sql`, `supabase/production-hardening.sql` e `supabase/audit-monitor-migration.sql` **não devem ser executados cegamente em produção**. Antes da aplicação, é necessário obter backup/dump ou comparar o schema remoto, identificar objetos já existentes e executar em homologação ou em blocos revisados.

O aviso da CLI sobre a versão instalada (`v3.2.0`, com `v3.4.0` disponível) não impediu os testes realizados. O parâmetro `--project-ref` na listagem de funções está depreciado para uma versão futura; usar `--remote=cryalcfhvoyyxijlorja` nas próximas execuções.


## Correção remota do Storage

A validação executada no projeto remoto revelou que o bucket `ativos-documentos` era privado, mas ainda possuía cinco políticas bucket-wide antigas, autorizando usuários autenticados apenas pela condição `bucket_id = 'ativos-documentos'`.

Foi aplicada a correção específica `supabase/apply-storage-isolation.sql`. A verificação posterior confirmou que as políticas antigas foram removidas e que permanecem somente políticas autorizadas por ativo/empresa para `SELECT`, `INSERT` e `UPDATE`. A função `public.can_access_asset_storage(text)` valida o Master, o perfil ativo, o padrão de caminho e o vínculo do usuário com a empresa efetiva do ativo. O bucket continua privado, com limite de 25 MB e MIME types PDF/imagens.

O teste de acesso com usuários reais ainda é necessário: Patrimonial autorizado deve acessar apenas seu ativo/empresa; Patrimonial não autorizado deve ser bloqueado; Master deve acessar todas as empresas.


## Validação do histórico remoto

A consulta de integridade do histórico remoto passou sem inconsistências:

- `events_without_asset`: 0
- `audit_asset_events_without_asset`: 0
- `audit_events_without_actor`: 0

Isso confirma que os eventos existentes referenciam ativos válidos e que os registros de auditoria existentes possuem responsável. Ainda é necessário executar operações reais em homologação para comprovar a classificação de eventos `TRANSFERENCIA`, `VENDA`, `BAIXA` e o bloqueio da auditoria para usuários Patrimoniais.


## Testes funcionais patrimoniais

Os testes que alterariam ativos — transferência, venda e baixa — foram deliberadamente não executados por decisão operacional. Portanto, a existência e integridade dos gatilhos e tabelas foram verificadas, mas a classificação funcional dos eventos durante uma operação real permanece pendente. A validação final desses três fluxos deve ocorrer posteriormente em homologação ou com ativos explicitamente destinados a teste.


## Pendência adicional de RLS encontrada

A revisão posterior das políticas mostrou que a política legada `Usuários autenticados consultam histórico de ativos` ainda permanecia em `public.asset_events`, simultaneamente à política restrita. Como políticas permissivas são combinadas por OR, essa duplicidade mantinha a leitura global do histórico.

O script `supabase/cleanup-legacy-rls.sql` foi corrigido para remover também essa política legada e recriar somente `Usuários autorizados consultam histórico de ativos`, limitada ao Master ou à empresa atual vinculada do ativo. A sequência consolidada foi regenerada com essa correção.


## Continuação da validação — 25/11/2026

O usuário confirmou a execução da limpeza de RLS. A listagem posterior mostrou que as políticas legadas de perfis, empresas, vínculos, ativos e documentos foram removidas. Foi identificada e corrigida no script a última política legada de leitura global de `asset_events`; a confirmação final deve mostrar somente `Usuários autorizados consultam histórico de ativos` nessa tabela.

Nova regressão local:

- JavaScript: **16/16 válidos** pelo `node --check`.
- Scripts referenciados pelo `index.html`: **10/10 presentes**, após normalização dos parâmetros de versão `?v=...`.
- Scripts Firebase carregados pelo `index.html`: **0**.
- Smoke test HTTP com `start-local-server.ps1`: inconclusivo nesta execução, pois o listener não permaneceu acessível entre processos; o script foi inspecionado e não houve alteração no frontend por causa desse resultado.


## Decisão operacional — seguir diretamente em produção

Foi decidido não criar ou utilizar um ambiente separado de homologação. A validação remota e as correções continuam direcionadas ao projeto de produção `AtivoFrota Imobilizado`.

Foi tentado um smoke test HTTP alternativo com Python e Node, mas os processos servidores iniciados pelo terminal não permaneceram acessíveis ao processo de requisição neste ambiente Windows. O `index.html`, seus 10 scripts referenciados e os 16 módulos JavaScript foram validados por inspeção e `node --check`; não foi feita alteração no código para contornar essa limitação operacional.


## Correção do card de ativos sem classificação

Foi identificado que o Supabase carregava ativos sem empresa com o rótulo `SEM CLASSIFICACAO` (sem acento), enquanto o dashboard filtrava pelo rótulo `SEM CLASSIFICAÇÃO` (com acento). Por isso, os 205 ativos sem empresa apareciam na base, mas o card mostrava zero. O fallback do carregamento remoto em `src/app.js` foi padronizado para `SEM CLASSIFICAÇÃO`; a sintaxe do arquivo foi validada novamente com `node --check`.
