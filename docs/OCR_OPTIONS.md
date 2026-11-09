# OCR local: estado atual e alternativas

Verificado em 8 de novembro de 2026. Nenhum modelo grande foi baixado e nenhum novo benchmark de inferência foi executado neste Mac.

**Ainda usamos Apple Vision.** `DocumentLoader` usa PDFKit para texto nativo; se a página tem pouco texto e OCR está habilitado, executa `VNRecognizeTextRequest` local. Separadamente, a extração multimodal manda imagens à OpenAI se o usuário habilitou cloud AI. Apple Vision OCR, visão do modelo OpenAI e modelos OCR abertos são três componentes diferentes.

A limitação observada foi uma falha CVPixelBuffer no ambiente de testes. Isso não demonstra que Vision seja inferior em acurácia. Para PDFs com texto nativo, preservar PDFKit evita reconstruir texto e perder correspondência de offsets.

## Comparação verificável

| Candidato | Evidência publicada | Encaixe no app |
|---|---|---|
| Apple Vision atual | Integração nativa e offline existente; sem resultado comparável medido no nosso corpus | Baseline, sem dependências/pesos adicionais; não reconstrói tabelas por si só |
| PaddleOCR-VL-1.6, 0.9B | OmniDocBench `v1.6_full`: overall 96.34, table TEDS 94.7619 | Candidato forte para estrutura/tabelas. O card oficial do pipeline ainda orienta macOS via Docker; exemplo Transformers é reconhecimento de elementos, não necessariamente pipeline completo |
| GLM-OCR, cerca de 0.9B | Mesmo quadro: overall 95.22, TEDS 92.83; upstream oferece guia Apple Silicon com mlx-vlm | Primeiro candidato de integração local no Mac pela rota MLX documentada e tamanho compacto |
| LightOnOCR-2-1B / LightOnOCR-3-4B | v2 documenta MPS; card v3 informa 86.3 em olmOCR-Bench | Candidatos alternativos, especialmente leitura/ordem. O 86.3 pertence a outro benchmark e não deve ser comparado numericamente com OmniDocBench |
| olmOCR 2, 7B | Pipeline aberto; instrução oficial de inferência local pede NVIDIA com ao menos 12 GB VRAM e 30 GB de disco | Boa referência de qualidade, menos direto para um app macOS autônomo nessa distribuição |

O leaderboard também inclui modelos acima desses, como OXR e TeleOCR. Estar no topo não estabelece disponibilidade dos pesos, licença de todos os componentes, suporte ao nosso Mac ou preservação de coordenadas. A shortlist considera engenharia local e requisitos de proveniência, não apenas a pontuação geral. Pontuações públicas não medem especificamente nossos erros de decimal, paciente/cluster, grupo ou cabeçalho.

Fontes primárias:

- [OmniDocBench, tabela v1.6_full](https://github.com/opendatalab/OmniDocBench#end-to-end-evaluation): números de comparação na mesma versão; overall combina texto, fórmulas e estrutura de tabela.
- [PaddleOCR-VL-1.6, card oficial](https://huggingface.co/PaddlePaddle/PaddleOCR-VL-1.6): Apache 2.0 e instruções de execução/pipeline. Seu card cita 96.33 em OmniDocBench v1.6; usei 96.34 do quadro atual do benchmark, sem misturar as duas medições.
- [GLM-OCR, modelo](https://huggingface.co/zai-org/GLM-OCR): pesos MIT; componente PP-DocLayoutV3 Apache 2.0. [Guia MLX oficial](https://github.com/zai-org/GLM-OCR/blob/main/examples/mlx-deploy/README.md).
- [LightOnOCR-2-1B](https://huggingface.co/lightonai/LightOnOCR-2-1B) e [LightOnOCR-3-4B](https://huggingface.co/lightonai/LightOnOCR-3-4B): Apache 2.0, suporte MPS documentado no exemplo v2 e resultado olmOCR-Bench publicado no card v3.
- [olmOCR, requisitos oficiais](https://github.com/allenai/olmocr#installation): pacote Apache 2.0; conferir separadamente a revisão/licença de pesos escolhidos.

## Decisão nesta versão

Manter PDFKit + Apple Vision funcionando e entregar as correções de integridade sem acrescentar um runtime Python/MLX obrigatório ao aplicativo. **Recomendação para a próxima comparação executada:** GLM-OCR/MLX e PaddleOCR-VL contra Vision, com LightOnOCR como terceiro candidato. Isso é uma recomendação de teste, não uma declaração de vencedor.

Prescrever antes do teste: conjunto fixo de páginas de Arts/Karlsson e scans de outros domínios; texto e células adjudicados por duas pessoas; versões de pesos/runtime fixadas; licenças registradas; entrada idêntica por engine. Medir exatidão de números/sinais/decimais, associação célula-cabeçalho, TEDS, CER/WER, ordem de leitura, boxes, tempo, pico de memória, tamanho da instalação e falhas. Registrar engine/modelo e offsets/boxes separadamente; nunca apresentar texto gerado como uma seleção nativa PDFKit. A engine pode terminar offline após baixar os pesos, mas memória, disco, energia e manutenção não são gratuitos.

A migração só deve ocorrer quando o candidato melhorar nossas métricas críticas no hardware real sem quebrar âncoras e distribuição. O protocolo de comparação está preparado; o benchmark local entre engines permanece pendente.
