# Padrão: Multitenancy no CMSX
> Aplica-se a: CMSX (Multiplai)

## Problema que resolve

O CMSX hospeda múltiplos clientes (tenants) no mesmo banco de dados. Cada tenant é uma `Aplicacao` com `Aplicacaoid` único. Sem isolamento, queries retornariam dados misturados entre tenants.

---

## Solução (diagrama ASCII)

```
Login (apelido + senha)
    │
    ▼
AcessoRepositorio.ValidaAcesso()
    │   retorna dynamic: { userid, aplicacaoid, url }
    ▼
JWT gerado com claims:
    - userid
    - aplicacaoid   ← chave de isolamento
    - acessoTotal
    - isDemo
    │
    ▼  (cada request autenticado)
Controller extrai aplicacaoid do JWT
    │
    ▼
Repositório recebe aplicacaoid
    │
    ▼
DAL filtra: WHERE Aplicacaoid = @aplicacaoid
```

---

## Entidade Aplicacao

```csharp
// CMSXData/Models/Aplicacao.cs
public partial class Aplicacao
{
    /// <summary>Id unico da aplicacao — chave de tenant</summary>
    public string? Aplicacaoid { get; set; }

    public string? Nome        { get; set; }
    public string? Url         { get; set; }
    public bool?   Isactive    { get; set; }
    public bool    IsDemo      { get; set; }  // dados resetados a cada login do tenant demo

    // perfil público (usado pela IA do Page Builder)
    public string? Telefone    { get; set; }
    public string? Descricao   { get; set; }
    // ...
}
```

**Tipo:** `string` — mesmo que pareça GUID, o campo é `string` no banco e no código. Não converter para `Guid` nas comparações.

---

## Como o aplicacaoid chega ao DAL

### 1. No login — AcessoRepositorio

```csharp
// CMSBLL/Repositorio/AcessoRepositorio.cs (camada legada)
public dynamic ValidaAcesso()
{
    dynamic _user = new ExpandoObject();
    DataTable dr = dal.ValidaAcesso();
    if (dr.Rows.Count == 1)
    {
        _user.userid      = new Guid(dr.Rows[0]["userid"].ToString());
        _user.aplicacaoid = new Guid(dr.Rows[0]["AplicacaoId"].ToString());
        _user.url         = dr.Rows[0]["Url"].ToString();
    }
    return _user;
}
```

### 2. Nas queries do DAL — filtro obrigatório

```csharp
// CMSXDAO/ProdutoDAL.cs — exemplo de query filtrada por tenant
public IEnumerable<Produto> ListaProduto()
{
    string appid = _localProps.appid; // aplicacaoid vindo do contexto da request
    CmsxDbContext db = new CmsxDbContext();
    return from prod in db.Produtos
           where prod.Aplicacaoid == appid
           select prod;
}
```

```sql
-- FormularioDAL.cs — exemplo em SQL raw
WHERE formulario.Ativo = 1 AND areas.AplicacaoId = @aplicacaoid
```

---

## Regras de isolamento

1. **Toda entidade com `Aplicacaoid` deve ser filtrada** — sem exceção
2. **`Aplicacaoid` é `string`** — nunca comparar como `Guid`
3. **Tenant `IsDemo = true`** — dados resetados a cada login; nunca persistir dados de produção aqui
4. **Claims JWT** — o `aplicacaoid` sempre vem do token, nunca de parâmetro de URL ou body (evita tenant spoofing)

---

## Entidades que possuem Aplicacaoid

| Entidade | Arquivo |
|---|---|
| `Aplicacao` | `CMSXData/Models/Aplicacao.cs` |
| `Area` | `CMSXData/Models/Area.cs` |
| `Produto` | `CMSXData/Models/Produto.cs` |
| `Conteudo` | `CMSXData/Models/Conteudo.cs` |
| `Formulario` | (via tabela `areas`) |

Novas entidades **devem** incluir `Aplicacaoid` se pertencerem a um tenant específico.

---

## Integração com Salematic

O Salematic é atualmente single-tenant. A proposta de integração é:

1. CMSX envia `Aplicacaoid` via header `X-Tenant-Key` ao chamar o Salematic
2. Salematic valida o JWT do CMSX e extrai `aplicacaoid` — sem login próprio
3. Salematic adiciona coluna `TenantId` nas tabelas: `Cliente`, `Pedido`, `Produto`, `Estoque`

Decisão registrada na memória: não criar sistema de autenticação próprio no Salematic — delegar para o JWT do CMSX.

---

## Pitfalls

| Problema | Causa | Fix |
|---|---|---|
| Query retorna dados de todos os tenants | Faltou filtro `WHERE Aplicacaoid = @appid` | Sempre filtrar no DAL |
| Comparação falha em runtime | `Aplicacaoid` comparado como `Guid` sendo `string` | Manter como `string` nas queries |
| Tenant demo com dados reais | `IsDemo` ignorado na lógica de reset | Verificar `IsDemo` antes de persistir dados críticos |
| Cross-tenant access | `aplicacaoid` extraído do body/URL | Extrair sempre do JWT via Claims |

---

## Ver também

- [cmsx-arch-ntier.md](cmsx-arch-ntier.md) — onde o filtro é aplicado nas camadas
- [cmsx-howto-novo-modulo.md](cmsx-howto-novo-modulo.md) — como criar entidade nova com `Aplicacaoid`
- [shared-pattern-saga.md](../shared/shared-pattern-saga.md) — integração CMSX ↔ Salematic que usa o tenant
