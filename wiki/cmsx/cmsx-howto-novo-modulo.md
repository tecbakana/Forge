# Como: Adicionar Novo Módulo ao CMSX
> Projeto: CMSX (Multiplai) | Ultima execução: 2026-04-13

## Pré-requisitos (checklist)

- [ ] Saber o nome da entidade (ex: `Pedido`)
- [ ] Ter o CMSX rodando localmente (`https://localhost:44455`)
- [ ] Entender a arquitetura N-Tier — ver [cmsx-arch-ntier.md](cmsx-arch-ntier.md)
- [ ] Branch de trabalho: `developer`

---

## Passos

### 1. Model — CMSXData/Models/

Criar o arquivo do model em `T:\Developer\RepositorioTrabalho\tecbakana\cmsx\CMSXData\Models\`.

```csharp
// CMSXData/Models/Pedido.cs
namespace CMSXData.Models
{
    public class Pedido
    {
        public Guid Pedidoid { get; set; }
        public string Aplicacaoid { get; set; }   // tenant — obrigatório para multi-tenancy
        public string ClienteNome { get; set; }
        public decimal ValorTotal { get; set; }
        public string Status { get; set; }         // ex: "pendente", "confirmado", "recusado"
        public DateTime DataCriacao { get; set; }
    }
}
```

> Toda entidade que pertence a um tenant **deve** ter `Aplicacaoid`. Ver [cmsx-pattern-multitenancy.md](cmsx-pattern-multitenancy.md).

### 2. DbContext — CMSXData/Models/CmsxDbContext.cs

Adicionar o `DbSet` na classe `CmsxDbContext`:

```csharp
// CMSXData/Models/CmsxDbContext.cs — adicionar dentro da classe:
public DbSet<Pedido> Pedidos { get; set; }
```

Se usar EF Migrations, rodar após esse passo:
```bash
dotnet ef migrations add AddPedido --project CMSXData --startup-project CMSXUI
dotnet ef database update --project CMSXData --startup-project CMSXUI
```

### 3. Interface DAL — ICMSX/IPedidoDAL.cs

```csharp
// ICMSX/IPedidoDAL.cs
using CMSXData.Models;

namespace ICMSX
{
    public interface IPedidoDAL
    {
        IEnumerable<Pedido> ListaPedidosPorAplicacao(string aplicacaoid);
        Pedido ObtemPedidoPorId(Guid id);
        void CriaPedido(Pedido pedido);
        void AtualizaStatus(Guid id, string status);
    }
}
```

### 4. Interface Repositório — ICMSX/IPedidoRepositorio.cs

```csharp
// ICMSX/IPedidoRepositorio.cs
using CMSXData.Models;

namespace ICMSX
{
    public interface IPedidoRepositorio
    {
        List<Pedido> ListaPedidos(string aplicacaoid);
        Pedido ObtemPedido(Guid id);
        void CriaPedido(Pedido pedido);
        void AtualizaStatus(Guid id, string status);
    }
}
```

### 5. DAL — CMSXDAO/PedidoDAL.cs

```csharp
// CMSXDAO/PedidoDAL.cs
using ICMSX;
using CMSXData.Models;

namespace CMSXDAO
{
    public class PedidoDAL : IPedidoDAL
    {
        private readonly CmsxDbContext _db;

        public PedidoDAL(CmsxDbContext db) { _db = db; }

        public IEnumerable<Pedido> ListaPedidosPorAplicacao(string aplicacaoid) =>
            _db.Pedidos.Where(p => p.Aplicacaoid == aplicacaoid).ToList();

        public Pedido ObtemPedidoPorId(Guid id) =>
            _db.Pedidos.FirstOrDefault(p => p.Pedidoid == id);

        public void CriaPedido(Pedido pedido)
        {
            _db.Pedidos.Add(pedido);
            _db.SaveChanges();
        }

        public void AtualizaStatus(Guid id, string status)
        {
            var pedido = _db.Pedidos.Find(id);
            if (pedido != null)
            {
                pedido.Status = status;
                _db.SaveChanges();
            }
        }
    }
}
```

### 6. Repositório — CMSXRepo/PedidoRepositorio.cs

```csharp
// CMSXRepo/PedidoRepositorio.cs
using CMSXData.Models;
using ICMSX;

namespace CMSXRepo
{
    public class PedidoRepositorio : BaseRepositorio, IPedidoRepositorio
    {
        private readonly IPedidoDAL _dal;

        public PedidoRepositorio(CmsxDbContext db, IPedidoDAL dal) : base(db)
        {
            _dal = dal;
        }

        public List<Pedido> ListaPedidos(string aplicacaoid) =>
            _dal.ListaPedidosPorAplicacao(aplicacaoid).ToList();

        public Pedido ObtemPedido(Guid id) =>
            _dal.ObtemPedidoPorId(id);

        public void CriaPedido(Pedido pedido) =>
            _dal.CriaPedido(pedido);

        public void AtualizaStatus(Guid id, string status) =>
            _dal.AtualizaStatus(id, status);
    }
}
```

### 7. Registro de DI — CMSXUI/Program.cs

```csharp
// CMSXUI/Program.cs — adicionar antes de builder.Build():
builder.Services.AddScoped<IPedidoDAL, PedidoDAL>();
builder.Services.AddScoped<IPedidoRepositorio, PedidoRepositorio>();
```

### 8. Controller — CMSXUI/Controllers/PedidosController.cs

```csharp
// CMSXUI/Controllers/PedidosController.cs
using Microsoft.AspNetCore.Mvc;
using ICMSX;
using CMSXData.Models;

namespace CMSXUI.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class PedidosController : ControllerBase
    {
        private readonly IPedidoRepositorio _repo;

        public PedidosController(IPedidoRepositorio repo)
        {
            _repo = repo;
        }

        [HttpGet("{aplicacaoid}")]
        public IActionResult ListaPedidos(string aplicacaoid)
        {
            var pedidos = _repo.ListaPedidos(aplicacaoid);
            return Ok(pedidos);
        }

        [HttpPost]
        public IActionResult CriaPedido([FromBody] Pedido pedido)
        {
            _repo.CriaPedido(pedido);
            return Created($"api/pedidos/{pedido.Pedidoid}", pedido);
        }
    }
}
```

---

## Checklist de conclusão

- [ ] Model criado em `CMSXData/Models/`
- [ ] `DbSet` adicionado ao `CmsxDbContext`
- [ ] Migration criada e aplicada (se EF Migrations em uso)
- [ ] Interface DAL criada em `ICMSX/`
- [ ] Interface Repositório criada em `ICMSX/`
- [ ] DAL implementado em `CMSXDAO/`
- [ ] Repositório implementado em `CMSXRepo/`
- [ ] DI registrado em `CMSXUI/Program.cs`
- [ ] Controller criado em `CMSXUI/Controllers/`
- [ ] Endpoint acessível no Swagger (`http://localhost:5124/swagger`)
- [ ] Build sem erros: `dotnet build CMSX.sln`

---

## Erros comuns

| Erro | Causa | Fix |
|---|---|---|
| `Unable to resolve service for type 'IXxxRepositorio'` | DI não registrado | Adicionar `AddScoped<IXxx, Xxx>()` em Program.cs |
| `Cannot use object of type 'System.String' for key` | `Aplicacaoid` é `string` mas foi comparado como `Guid` | Manter como `string` no model e nas queries |
| Build error em CMSXRepo/CMSXDAO: referência não encontrada | Projeto não referencia ICMSX ou CMSXData | Verificar `.csproj` de cada projeto — dependências devem seguir o fluxo N-Tier |
| Controller acessa `CmsxDbContext` diretamente | Atalho errado | Injetar apenas `IXxxRepositorio` no controller |

---

## Ver também

- [cmsx-arch-ntier.md](cmsx-arch-ntier.md) — visão geral das camadas
- [cmsx-pattern-multitenancy.md](cmsx-pattern-multitenancy.md) — como usar `Aplicacaoid` corretamente
- [cmsx-swagger-bearer.md](cmsx-swagger-bearer.md) — testar endpoint no Swagger com JWT
