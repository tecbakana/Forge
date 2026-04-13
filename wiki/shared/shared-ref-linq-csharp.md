# LINQ — Referência Rápida C#

LINQ (Language Integrated Query) permite manipular coleções de forma declarativa e encadeada.

---

## Operadores essenciais

### Where — Filtrar
```csharp
var pendentes = requests.Where(r => r.Status == "pendente").ToList();
```

### Select — Transformar (map)
```csharp
var nomes = produtos.Select(p => p.Nome).ToList();

// Projetar em tipo anônimo
var resumo = produtos.Select(p => new { p.Nome, p.Preco }).ToList();
```

### SelectMany — Achatar lista de listas
```csharp
// "teclado mecânico" → ["teclado", "mecânico"]
var termos = entrada
    .SelectMany(t => t.Split(' ', StringSplitOptions.RemoveEmptyEntries))
    .Distinct()
    .ToList();
```

### First / FirstOrDefault — Buscar um elemento
```csharp
var produto = lista.FirstOrDefault(p => p.Id == id);
// retorna null se não encontrar, sem lançar exceção
```

### Any / All — Verificar existência
```csharp
var temEstoque = produtos.Any(p => p.Quantidade > 0);
var todosAtivos = itens.All(i => i.Ativo);
```

### Sum / Count / Min / Max — Agregar
```csharp
var total    = itens.Sum(i => i.Preco * i.Quantidade);
var qtd      = lista.Count(x => x.Status == "ativo");
var maisBarato = produtos.Min(p => p.Preco);
```

### OrderBy / OrderByDescending — Ordenar
```csharp
var ordenados = produtos.OrderBy(p => p.Preco).ToList();
var recentes  = pedidos.OrderByDescending(p => p.Data).ToList();
```

### GroupBy — Agrupar
```csharp
var porStatus = pedidos.GroupBy(p => p.Status);
foreach (var grupo in porStatus)
{
    Console.WriteLine($"{grupo.Key}: {grupo.Count()} pedidos");
}
```

### Distinct — Remover duplicatas
```csharp
var unicos = lista.Select(x => x.Categoria).Distinct().ToList();
```

---

## Encadeamento — padrão mais comum

```csharp
var resultado = produtos
    .Where(p => p.Estoque > 0)
    .OrderBy(p => p.Preco)
    .Select(p => new { p.Nome, p.Preco })
    .ToList();
```

---

## Dicas

| Objetivo | Método |
|---|---|
| Filtrar | `Where` |
| Transformar | `Select` |
| Achatar | `SelectMany` |
| Pegar um | `FirstOrDefault` |
| Verificar se existe | `Any` |
| Somar | `Sum` |
| Ordenar | `OrderBy` |
| Remover duplicatas | `Distinct` |
| Agrupar | `GroupBy` |

> Sempre terminar com `.ToList()` ou `.ToArray()` para materializar a query. Sem isso, a execução é lazy (adiada).

---

## Caso real — Salematic

Quebrar termo de busca composto em múltiplos termos individuais:

```csharp
var subTermos = termos
    .SelectMany(t => t.Split(' ', StringSplitOptions.RemoveEmptyEntries))
    .Distinct()
    .ToList();
// "teclado mecânico" → ["teclado", "mecânico"]
// busca separada por cada termo, resultados deduplicados por ID
```
