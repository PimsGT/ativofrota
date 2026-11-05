# Modelo Firebase — AtivoFrota

A migração deve acontecer antes do vínculo definitivo das notas fiscais. Os arquivos originais permanecem na pasta local como fonte de conferência; a cópia operacional vai para o Firebase Storage e seus metadados ficam no Firestore.

## Ordem de implantação

1. Criar Firebase Authentication, Firestore e Storage.
2. Publicar as regras de segurança.
3. Criar os documentos de configuração das empresas e perfis.
4. Importar os 497 ativos com identificadores normalizados.
5. Importar as 312 notas fiscais para o Storage, sem apagar ou renomear os originais.
6. Extrair do nome do arquivo NF: número, chassi/série candidato e empresa da pasta.
7. Criar sugestões de vínculo; confirmar automaticamente apenas quando o identificador for exato.
8. Revisar duplicidades e associar NF antecessora, aquisição, venda ou transferência.
9. Marcar as 14 imagens existentes como `referenceImages`, não como fotos oficiais dos ativos.
10. Liberar o gerenciamento no app: editar ativo, substituir documentos, adicionar imagens e consultar histórico.

## Firestore

```text
companies/{companyId}
  name: AGRO IPUÃ | SANTA MARIA | SERRA BRANCA
  cnpj: string
  active: boolean

users/{uid}
  displayName: string
  role: admin | patrimonial | auditor | consulta
  companyIds: string[]

assets/{assetId}
  name: string
  companyId: string
  category: string
  brand: string
  model: string
  chassis: string
  serialNumber: string
  year: number
  acquisitionDate: timestamp | null
  operationalLocation: string
  status: string
  ageYears: number
  ageBand: novo | 1-5 | 6-10 | 11-15 | acima-15 | sem-data
  documentCount: number
  officialPhotoCount: number
  createdAt: timestamp
  updatedAt: timestamp
  updatedBy: uid

assets/{assetId}/documents/{documentId}
  documentType: aquisicao | antecessora | venda | transferencia | complementar | outro
  nfNumber: string
  issueDate: timestamp | null
  supplier: string
  companyId: string
  chassisExtracted: string
  fileName: string
  storagePath: string
  matchStatus: automatico | confirmado | sugerido | pendente | rejeitado
  sourceFolder: string
  uploadedAt: timestamp
  uploadedBy: uid

assets/{assetId}/photos/{photoId}
  fileName: string
  storagePath: string
  caption: string
  isOfficialAssetPhoto: boolean
  uploadedAt: timestamp
  uploadedBy: uid

transfers/{transferId}
  assetId: string
  fromCompanyId: string
  toCompanyId: string
  reason: string
  transferDocumentId: string | null
  transferredAt: timestamp
  transferredBy: uid

assetHistory/{historyId}
  assetId: string
  action: created | updated | document-added | document-replaced | photo-added | transfer
  before: map
  after: map
  userId: uid
  createdAt: timestamp
```

## Storage

```text
assets/{assetId}/documents/{documentId}-{safeFileName}
assets/{assetId}/photos/{photoId}-{safeFileName}
reference-images/{fileName}
imports/{batchId}/original/{fileName}
```

Uma NF antecessora não substitui a NF atual. As duas permanecem em `documents` e a ficha do ativo mostra a cadeia documental completa.

## Idade dos bens

A idade deve usar primeiro `acquisitionDate`. Se essa data não existir, usa-se o ano do ativo como estimativa. Fórmula: `idade = ano atual - ano de aquisição`. O app deve apresentar idade em anos e faixa: novo, 1–5, 6–10, 11–15, acima de 15 ou sem data.

Filtros gerenciais: empresa, categoria, marca, status, faixa de idade, ano, com NF/sem NF, com foto/sem foto e documentos pendentes de confirmação.
