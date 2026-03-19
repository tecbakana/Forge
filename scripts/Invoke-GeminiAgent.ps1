# =============================================================================
# Invoke-GeminiAgent.ps1
# Agente conversacional com function calling via Gemini
# =============================================================================

$GeminiTools = @(
    @{
        name        = "switch_environment"
        description = "Troca o ambiente de desenvolvimento (developer, homolog, master), aplica configs e opcionalmente faz git pull e abre o Visual Studio."
        parameters  = @{
            type       = "object"
            properties = @{
                environment = @{ type = "string"; enum = @("developer","homolog","master"); description = "Ambiente alvo" }
                client      = @{ type = "string"; description = "Cliente ex: default, cliente1. Se nao informado usa default" }
                apis        = @{ type = "string"; description = "APIs separadas por virgula ex: TaaS,TaxEngineRest. Se nao informado usa all" }
                gitPull     = @{ type = "boolean"; description = "Se deve fazer git pull" }
                openVS      = @{ type = "boolean"; description = "Se deve abrir o Visual Studio" }
                closeVS     = @{ type = "boolean"; description = "Se deve fechar o Visual Studio antes" }
                force       = @{ type = "boolean"; description = "Ignorar alteracoes nao commitadas" }
            }
            required   = @("environment")
        }
    },
    @{
        name        = "get_git_status"
        description = "Retorna os arquivos modificados, adicionados ou deletados em uma API especifica."
        parameters  = @{
            type       = "object"
            properties = @{
                api = @{ type = "string"; description = "Nome da API ex: TaaS" }
            }
            required   = @("api")
        }
    },
    @{
        name        = "get_git_ahead_behind"
        description = "Verifica quantos commits a branch local esta a frente ou atras do remoto."
        parameters  = @{
            type       = "object"
            properties = @{
                api = @{ type = "string"; description = "Nome da API. Se nao informado verifica todas." }
            }
            required   = @()
        }
    },
    @{
        name        = "list_branches"
        description = "Lista as branches locais de uma API."
        parameters  = @{
            type       = "object"
            properties = @{
                api = @{ type = "string"; description = "Nome da API ex: TaaS" }
            }
            required   = @("api")
        }
    },
    @{
        name        = "get_current_status"
        description = "Retorna o status atual de todas as APIs: ambiente, cliente, branch e desktop."
        parameters  = @{
            type       = "object"
            properties = @{}
            required   = @()
        }
    }
)

function Invoke-GeminiAgent {
    param(
        [string]$Message,
        [string]$ApiKey,
        [string]$Model,
        [string]$Url,
        [array]$History = @(),
        [string]$SystemContext
    )

    $url = "https://generativelanguage.googleapis.com/$($Url)/models/$($Model):generateContent?key=$ApiKey"

    # Monta o corpo da requisição
    $body = @{
        system_instruction = @{
            parts = @(@{ text = $SystemContext })
        }
        contents = @(
            $History + @(@{
                role  = "user"
                parts = @(@{ text = $Message })
            })
        )
        tools = @(@{
            function_declarations = $GeminiTools
        })
    } | ConvertTo-Json -Depth 20
	$maxRetries = 3
	$retry = 0
	while ($retry -lt $maxRetries) {
		try {
			$response = Invoke-RestMethod -Uri $url -Method POST -Body $body -ContentType "application/json"
			$part     = $response.candidates[0].content.parts[0]

			# Retornou uma tool call?
			if ($part.functionCall) {
				return @{
					type     = "toolCall"
					name     = $part.functionCall.name
					args     = $part.functionCall.args
					rawPart  = $part
				}
			}

			# Retornou texto normal
			return @{
				type = "text"
				text = $part.text
			}
		} catch {
			return @{
				type  = "error"
				error = $_.Exception.Message
			}
		}
	}
}

function Send-GeminiToolResult {
    param(
        [string]$ApiKey,
        [string]$Model,
		[string]$Url,
        [array]$History,
        [string]$ToolName,
        [object]$ToolResult,
        [string]$SystemContext
    )

    $url = "https://generativelanguage.googleapis.com/$($Url)/models/$($Model):generateContent?key=$ApiKey"

    $resultContent = @{
        role  = "function"
        parts = @(@{
            functionResponse = @{
                name     = $ToolName
                response = @{ result = ($ToolResult | ConvertTo-Json -Depth 10) }
            }
        })
    }

    $body = @{
        system_instruction = @{
            parts = @(@{ text = $SystemContext })
        }
        contents = $History + @($resultContent)
        tools    = @(@{ function_declarations = $GeminiTools })
    } | ConvertTo-Json -Depth 20
	$maxRetries = 3
	$retry = 0
	while ($retry -lt $maxRetries) {
		try {
			$response = Invoke-RestMethod -Uri $url -Method POST -Body $body -ContentType "application/json"
			$text     = $response.candidates[0].content.parts[0].text
			return @{ type = "text"; text = $text }
		} catch {
			return @{ type = "error"; error = $_.Exception.Message }
		}
	}
}