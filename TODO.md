

## Firebase e ciclo de vida do ativo

- [x] Definir modelo Firestore para empresas, ativos, documentos, fotos, transferências e histórico.
- [x] Definir caminhos do Firebase Storage para NFs, fotos oficiais, imagens de referência e originais de importação.
- [x] Criar regras iniciais de segurança para perfis administrador, patrimonial, auditor e consulta.
- [x] Definir importação das 312 NFs sem sobrescrever documentos antecessores.
- [x] Separar imagens de referência da planilha de fotos oficiais dos ativos.
- [x] Definir cálculo de idade e faixas para filtros gerenciais.
- [ ] Criar o projeto Firebase real e aplicar `firestore.rules` e `storage.rules`.
- [ ] Criar o usuário administrador inicial e as três empresas.
- [ ] Executar a importação dos 497 ativos.
- [ ] Executar a carga das 312 NFs no Storage.
- [ ] Revisar sugestões de vínculo e confirmar documentos ambíguos.
- [ ] Implementar edição completa do ativo com substituição versionada de documentos e fotos.


## Evolução multiusuário com Supabase

- [ ] Aplicar no Supabase as migrações de segurança, histórico, documentos, empresas e vínculos de usuários.
- [ ] Garantir que a aplicação não carregue ativos fictícios nem mantenha operações patrimoniais somente no localStorage.
- [ ] Persistir novos ativos, transferências, classificações, documentos e fotos no Supabase com confirmação de linhas afetadas.
- [ ] Corrigir identidade, logout, senha provisória, autorização Master e escaping de dados exibidos.
- [ ] Remover referências funcionais ao Firebase do frontend; manter Firebase somente como hospedagem.
- [ ] Configurar o Firebase Hosting e publicar após validar o projeto Supabase e a Edge Function.


## Monitor de auditoria Master

- [x] Criar trilha de eventos no Supabase com ator, empresa, registro, tipo, metadados e data/hora.
- [x] Restringir a consulta da auditoria ao perfil Master.
- [x] Substituir a tela estática por filtros de empresa, evento e período.
- [ ] Executar `supabase/audit-monitor-migration.sql` no projeto de produção.
- [ ] Publicar a versão do Hosting após a migração.
