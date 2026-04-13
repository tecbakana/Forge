# CMSX — Arquitetura N-Tier
> Status: estável

## Visão geral em uma frase

O CMSX segue arquitetura N-Tier com cinco camadas: apresentação (CMSXUI), repositório (CMSXRepo), interfaces (ICMSX), acesso a dados (CMSXDAO) e modelos/domínio (CMSXData).

---

## Diagrama (ASCII)

```
┌─────────────────────────────────────────────────────────┐
│  CMSXUI  (ASP.NET Core + Angular — porta 44455)         │
│  Controllers/ + ClientApp/                              │
│  Recebe requests HTTP, retorna JSON ou View             │
└───────────────┬─────────────────────────────────────────┘
                │  injeção de dependência (IXxxRepositorio)
                ▼
┌─────────────────────────────────────────────────────────┐
│  CMSXRepo  (Repositório)                                │
│  AplicacaoRepositorio, ProdutoRepositorio, ...          │
│  Orquestra lógica de negócio, chama DAL                 │
└──────────┬────────────────────┬────────────────────────┘
           │ implementa         │ consome
           ▼                    ▼
┌────────────────┐   ┌──────────────────────────────────┐
│  ICMSX         │   │  CMSXDAO  (Acesso a dados)        │
│  (Interfaces)  │   │  AplicacaoDAL, ProdutoDAL, ...    │
│  IXxxRepo      │◄──│  Queries SQL via EF Core          │
│  IXxxDAL       │   │  Recebe CmsxDbContext              │
└────────────────┘   └──────────┬───────────────────────┘
                                │ usa
                                ▼
                   ┌────────────────────────────────────┐
                   │  CMSXData  (Modelos / Domínio)      │
                   │  Models/: Aplicacao, Area,          │
                   │  Produto, Usuario, ...              │
                   │  CmsxDbContext (EF Core DbContext)  │
                   └────────────────────────────────────┘
```

**Fluxo obrigatório:** `CMSXUI → CMSXRepo → (ICMSX) ← CMSXDAO ← CMSXData`

---

## Projetos e responsabilidades

| Projeto | Responsabilidade | Referencia |
|---|---|---|
| `CMSXUI` | Controllers API + Angular SPA | CMSXRepo (via ICMSX) |
| `CMSXRepo` | Lógica de negócio, orquestração | ICMSX, CMSXData |
| `ICMSX` | Contratos (interfaces) | CMSXData (modelos) |
| `CMSXDAO` | Queries EF Core / SQL | CMSXData (DbContext + Models) |
| `CMSXData` | Modelos de domínio, DbContext | — |

**Caminho base:** `T:\Developer\RepositorioTrabalho\tecbakana\cmsx\`

---

## Exemplo com código real — AplicacaoRepositorio

```csharp
// CMSXRepo/AplicacaoRepositorio.cs
namespace CMSXRepo
{
    public class AplicacaoRepositorio : BaseRepositorio, IAplicacaoRepositorio
    {
        private readonly IAplicacaoDAL _dal;

        // DI: recebe DbContext e DAL via construtor
        public AplicacaoRepositorio(CmsxDbContext db, IAplicacaoDAL dal) : base(db)
        {
            _dal = dal;
        }

        public Aplicacao ObtemAplicacaoPorId(Guid id) => _dal.ObtemPorId(id);
        public List<Aplicacao> ListaAplicacao()       => _dal.ListaTodos();
    }
}
```

```csharp
// ICMSX/IAplicacaoRepositorio.cs
public interface IAplicacaoRepositorio
{
    Aplicacao ObtemAplicacaoPorId(Guid id);
    List<Aplicacao> ListaAplicacao();
    // ...
}
```

```csharp
// CMSXDAO/AplicacaoDAL.cs
public class AplicacaoDAL : IAplicacaoDAL
{
    private readonly CmsxDbContext _db;
    public AplicacaoDAL(CmsxDbContext db) { _db = db; }

    public Aplicacao ObtemPorId(Guid id) =>
        _db.Aplicacaos.FirstOrDefault(a => a.Aplicacaoid == id);
}
```

---

## Registro de DI — Program.cs (CMSXUI)

```csharp
// Padrão de registro para cada módulo:
builder.Services.AddScoped<IAplicacaoRepositorio, AplicacaoRepositorio>();
builder.Services.AddScoped<IAplicacaoDAL, AplicacaoDAL>();
```

---

## Regras que nunca se quebram

1. **Controller não acessa DAL diretamente** — sempre via Repositório
2. **DAL não contém lógica de negócio** — só queries
3. **Repositório não conhece implementações concretas do DAL** — depende de interfaces (`IAplicacaoDAL`)
4. **Refatorações que alterem a estrutura de camadas exigem plano aprovado** antes de qualquer código

---

## Modelos principais (CMSXData/Models/)

| Model | Descrição |
|---|---|
| `Aplicacao` | Tenant — cada aplicação é um tenant |
| `Usuario` | Usuário do sistema (apelido + senha plain text — legado) |
| `Area` | Página/layout, isolada por `Aplicacaoid` |
| `Produto` | Produto de e-commerce, isolado por `Aplicacaoid` |
| `CmsxDbContext` | DbContext EF Core — ponto de acesso ao banco |

Multi-tenancy: toda entidade com `Aplicacaoid` está isolada por tenant. Ver [cmsx-pattern-multitenancy.md](cmsx-pattern-multitenancy.md).

---

## Conexão com outros projetos

- **Salematic** consome dados do CMSX via Azure Service Bus (tópico `top-pedidos`) — não acessa o banco diretamente
- **Integração SAGA:** CMSXUI publica pedidos e consome status — ver [shared-pattern-saga.md](../shared/shared-pattern-saga.md)

---

## Pitfalls conhecidos

| Problema | Causa | Fix |
|---|---|---|
| Controller acessa `CmsxDbContext` diretamente | Atalho de desenvolvimento | Mover para DAL + Repo |
| DAL com lógica de negócio | Acumulou regras ao longo do tempo | Mover para Repositório ao refatorar |
| Interface não criada em ICMSX | Esqueceu o contrato | Criar `IXxxDAL` e `IXxxRepositorio` antes da implementação |
| DI não registrado | Novo DAL/Repo sem registro no Program.cs | `AddScoped<IXxx, Xxx>()` — ver seção DI acima |
