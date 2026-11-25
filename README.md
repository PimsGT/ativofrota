# AtivoFrota — Imobilizado & Frotas

MVP funcional para transformar a planilha de máquinas e frotas em um app web responsivo, com dashboard, inventário, auditoria e relatórios.

## Executar agora
Não requer Node.js nem instalação. Abra `index.html` no navegador. Para uso local com servidor estático, qualquer servidor HTTP simples pode ser usado.

A base inicial foi modelada a partir de `Controle de Máquinas e Frotas 2025.xlsm`, com 497 ativos classificados. O cadastro de novos ativos é persistido no `localStorage` do navegador.

## GitHub
1. Crie um repositório privado ou interno no GitHub.
2. Dentro desta pasta, execute `git init`, `git add .` e `git commit -m "feat: inicializa AtivoFrota"`.
3. Adicione o remoto do repositório e faça `git push -u origin main`.
4. Para publicação, use GitHub Pages, Firebase Hosting ou outro serviço estático.

## Firebase
Para transformar o MVP em multiusuário:

1. Crie um projeto no Firebase Console.
2. Ative Authentication (Google ou e-mail), Firestore Database e Storage.
3. Registre um app Web e copie a configuração para um arquivo local `src/firebase-config.js` a partir de `src/firebase-config.example.js`.
4. Nunca coloque service account, chave privada ou credencial administrativa no frontend.
5. Mova a fonte de dados de `localStorage` para uma coleção `assets` no Firestore.
6. Use `auditLogs` para a trilha de auditoria e `documents` para notas fiscais/imagens no Storage.
7. Publique com Firebase Hosting ou conecte o build a partir do GitHub.

## Próximo passo recomendado
Validar com o responsável patrimonial quais registros da aba EQUIPAMENTOS devem ser considerados “conferidos”, “revisar” ou “pendentes” antes da importação definitiva para o Firestore.


## Gestão das três empresas

O app agora separa a base entre **AGRO IPUÃ**, **SANTA MARIA** e **SERRA BRANCA**. Use o seletor no topo ou os cartões do dashboard para mudar a empresa em foco. No inventário, o filtro Empresa combina com busca, categoria e status.

Para transferir um ativo, abra o Inventário, clique em **Transferir ativo** ou no ícone `⇄` da linha desejada, selecione a empresa de destino e informe o motivo. A empresa proprietária é atualizada imediatamente na base local, e a transferência fica registrada com origem, destino, data e responsável.

Na integração Firebase, recomendamos as coleções `assets`, `transfers` e `auditLogs`. A operação de transferência deve usar uma transação do Firestore para atualizar o ativo e gravar o evento de auditoria juntos.


## Ficha do ativo e documentos

O inventário agora possui uma ação de visualização (`◉`) em cada linha. A ficha exibe empresa, categoria, ano, local, status, nota fiscal e foto vinculadas. Quando disponíveis, a NF pode ser baixada diretamente e a foto é exibida na própria ficha.

O cadastro de ativo aceita NF em PDF/JPG/PNG e uma imagem do ativo. A transferência também permite pesquisar o ativo, filtrar por empresa e categoria e atualizar a NF ou a imagem durante a movimentação. O tema claro/escuro é persistido no navegador.


## Estratégia correta para Firebase e documentos

A sequência recomendada é criar primeiro o Firebase, aplicar as regras de segurança e preparar os caminhos de Storage. Depois disso, os ativos, as 312 notas fiscais e os metadados são importados. O vínculo com cada ativo ocorre somente após a extração e normalização do chassi ou número de série.

A estrutura detalhada está em `firebase-data-model.md`. As regras iniciais estão em `firestore.rules` e `storage.rules`. A importação mantém os arquivos originais e suporta várias NFs por ativo, incluindo NF antecessora, aquisição, venda, transferência e complementar.

## Gerenciamento contínuo

A ficha do ativo deve permitir editar seus dados, substituir ou adicionar documentos, adicionar ou remover fotos oficiais, baixar NFs e consultar o histórico. Substituições não devem apagar a trilha anterior: o arquivo antigo permanece no Storage com registro de histórico e o documento novo recebe uma nova versão.

## Idade e filtros

A idade do bem será calculada pela data de aquisição; quando ela não existir, o sistema usa o ano cadastrado como estimativa. O dashboard e os relatórios poderão filtrar por empresa, categoria, idade, faixa etária, status, presença de NF, presença de foto e pendência de vínculo.

A pasta `Imagens` da raiz contém 14 arquivos usados como referência da planilha. Esses arquivos serão importados, se necessário, para `reference-images` e nunca serão marcados automaticamente como fotos oficiais dos ativos.


## Firebase conectado

O app Web está configurado para o projeto `ativofrota-imobilizado`. A inicialização modular está em `src/firebase-init.js` e usa Authentication, Firestore, Storage e Analytics. A configuração pública do app está em `src/firebase-config.js`; ela não contém credenciais administrativas.

Antes da primeira sincronização, habilite no Firebase Console o Authentication, o Firestore Database e o Storage. Depois, publique as regras com o Firebase CLI:

```powershell
firebase login
firebase use ativofrota-imobilizado
firebase deploy --only firestore:rules,storage
```

O app continua funcionando em modo local enquanto os serviços ainda não estiverem habilitados. O cadastro local não substitui a migração; a carga definitiva seguirá o modelo em `firebase-data-model.md`.

## Idade dos ativos no dashboard

O dashboard agora terá um painel de idade estimada. Ele apresenta a idade média e a distribuição em faixas: novo, 1–5, 6–10, 11–15, acima de 15 anos e sem data. Os filtros permitem visão geral, empresa e categoria. A data de aquisição será a fonte preferencial; na ausência dela, o ano cadastrado será usado como estimativa.


## Configuração Supabase

A URL base configurada para o projeto é `https://cryalcfhvoyyxijlorja.supabase.co`. O trecho `/rest/v1/` não deve ser usado como URL principal do cliente; ele é apenas o caminho da API REST. A chave usada é uma chave pública `sb_publishable_`, adequada para o frontend quando as políticas RLS estão configuradas.

Nunca colocar no frontend a senha do banco, `service_role`, secret key ou qualquer token administrativo. A configuração local está em `src/supabase-config.js` e o modelo sem credenciais está em `src/supabase-config.example.js`.


## Controle de usuários pelo Master

O controle de acesso usa o Supabase Auth e a tabela `public.profiles`, com apenas dois perfis: `master` e `patrimonial`. O perfil Master pode abrir **Usuários e acessos** e criar uma conta com senha provisória. A conta é criada por uma Edge Function protegida; a chave `service_role` não é enviada ao navegador. No primeiro login, o usuário fica bloqueado pelo modal de troca de senha até definir uma nova senha.

### Implantação inicial

1. No Supabase SQL Editor, execute `supabase-user-access.sql`.
2. Crie ou confirme o primeiro usuário Master em **Authentication > Users** no Supabase.
3. Copie o UUID desse usuário e execute no SQL Editor:

```sql
insert into public.profiles (id, display_name, role, must_change_password, active)
values ('UUID_DO_USUARIO_MASTER', 'Leonardo Aguiar', 'master', false, true)
on conflict (id) do update set role = 'master', must_change_password = false, active = true;
```

4. Com o Supabase CLI autenticado e vinculado ao projeto, publique a função:

```powershell
supabase login
supabase link --project-ref cryalcfhvoyyxijlorja
supabase functions deploy admin-create-user
```

A função usa automaticamente `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY` no ambiente seguro do Supabase. Nunca copie a `service_role` para `src`, `index.html` ou qualquer arquivo publicado.

### Uso no app

Depois de entrar como Master, abra **Usuários** no menu lateral, informe nome, e-mail, perfil e senha provisória com pelo menos oito caracteres. Entregue a senha provisória por um canal seguro. O usuário Patrimonial poderá acessar as rotinas operacionais, mas não verá a administração de usuários. No primeiro login, o app exigirá a definição de uma nova senha antes de liberar o dashboard.

## Arquitetura final e publicação

O AtivoFrota usa o **Supabase** para autenticação, perfis, empresas, ativos, histórico, documentos e fotos. O **Firebase é somente o hosting** dos arquivos estáticos; Firebase Auth, Firestore, Firebase Storage e Analytics não são usados pelo app.

Antes da primeira publicação, execute no SQL Editor do Supabase, nesta ordem: `supabase-user-access.sql`; se houver carga inicial, `assets-import-setup.sql` ou `assets-import-stage.sql`, seguido da importação de `assets-import.csv` e do bloco de finalização; depois `assets-rls-master-access.sql`, `asset-lifecycle-migration.sql`, `supabase/production-hardening.sql` e `supabase/audit-monitor-migration.sql`. As políticas temporárias da importação são substituídas pelo RLS final. Depois, publique a Edge Function `supabase/functions/admin-create-user` e confirme as políticas do bucket privado `ativos-documentos`.

Para publicar no Firebase Hosting, autentique o Firebase CLI, selecione o projeto correto e execute `firebase deploy --only hosting`. O `firebase.json` bloqueia CSVs, SQLs, arquivos de configuração sensíveis, regras e a pasta de funções. O arquivo `src/supabase-config.public.js` contém apenas a configuração pública necessária ao navegador; nunca coloque `service_role`, senha de banco ou token administrativo no frontend.

O backup desta evolução foi criado na pasta irmã `app-imobilizado-backup-20261118-085730`.


### Monitor de auditoria Master

O arquivo `supabase/audit-monitor-migration.sql` cria a trilha `audit_events`, com eventos de cadastro, alteração, transferência, venda, baixa, reclassificação e documentos. A leitura é exclusiva do perfil `master`. Execute essa migração após as demais migrações e publique novamente o Hosting para disponibilizar o painel **Auditoria**.


## Nota de arquitetura vigente — atualização da auditoria

As seções antigas deste README que mencionam Firebase Authentication, Firestore ou Firebase Storage são referências históricas do MVP e não fazem parte da arquitetura vigente. O backend oficial do AtivoFrota é o Supabase: Auth, Postgres, RLS, Storage e Edge Functions. O Firebase, se utilizado, deve ser usado somente para Hosting estático.

A sequência consolidada de correções SQL está em `supabase/APPLY-CORRECTIONS-SEQUENCE.sql`. Ela não inclui scripts de importação e deve ser revisada antes de execução no projeto remoto correto. Os scripts de validação e correção específicos ficam na mesma pasta `supabase/`.
