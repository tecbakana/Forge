# CMSX — Swagger com Bearer JWT

Configuração para expor e testar a API do CMSX via Swagger UI com autenticação JWT.

---

## Portas (dev)

| Serviço | URL |
|---------|-----|
| Angular (SPA proxy) | https://localhost:44455 |
| .NET API | http://localhost:5124 |
| Swagger UI | http://localhost:5124/swagger |

---

## Program.cs — configuração completa

```csharp
// 1. Registrar serviços
builder.Services.AddEndpointsApiExplorer();

builder.Services.AddCors(options =>
{
    options.AddPolicy("Dev", policy =>
        policy.WithOrigins("https://localhost:44455", "http://localhost:5124")
              .AllowAnyHeader()
              .AllowAnyMethod());
});

builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "CMSX API", Version = "v1" });
    c.AddServer(new OpenApiServer { Url = "http://localhost:5124" });
    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Name         = "Authorization",
        Type         = SecuritySchemeType.Http,
        Scheme       = "bearer",
        BearerFormat = "JWT",
        In           = ParameterLocation.Header,
        Description  = "Informe o token JWT obtido em /auth/login"
    });
    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" }
            },
            Array.Empty<string>()
        }
    });
});

// 2. Pipeline (ordem importa)
app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "CMSX API v1");
    c.RoutePrefix = "swagger";
});

app.UseStaticFiles();
app.UseRouting();
app.UseCors("Dev");         // antes de UseAuthentication
app.UseAuthentication();
app.UseAuthorization();
```

---

## Obtendo o token

```bash
curl -X POST http://localhost:5124/auth/login \
  -H "Content-Type: application/json" \
  -d '{"apelido": "USUARIO", "senha": "SENHA"}'
```

Resposta: `{ "token": "eyJ..." }`

Ou use o endpoint demo (sem credenciais):
```bash
curl -X POST http://localhost:5124/auth/demo-login
```

---

## Usando no Swagger UI

1. Acesse `http://localhost:5124/swagger`
2. Clique em **Authorize** (canto superior direito)
3. Cole o token no campo e confirme
4. Todos os endpoints protegidos passam a enviar `Authorization: Bearer {token}`

---

## Por que CORS é necessário

O Swagger UI é servido pelo Angular (`https://localhost:44455`) mas faz chamadas ao .NET (`http://localhost:5124`). Origens diferentes exigem CORS explícito — sem isso o browser bloqueia com `Failed to fetch`.
