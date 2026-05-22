# Arquitetura (template reutilizável)

Este projeto foi reorganizado para um formato **feature-first** com `lib/src/`, fácil de copiar para outros apps e crescer sem virar um `lib/` gigante.

## Estrutura de pastas

```
lib/
  main.dart
  src/
    app/
      app.dart
      theme/
        app_theme.dart

    features/
      stickers/
        data/
          pack_storage.dart
          sticker_manager.dart
        domain/
          sticker_pack_info.dart
        presentation/
          home_page.dart
          widgets/
            home_floating_button.dart

    shared/
      widgets/
        base_app_bar.dart
```

### Regras rápidas (para manter “dinâmico”)

- **`main.dart`**: só bootstrap (`ensureInitialized`) + `runApp`.
- **`src/app/`**: raiz do app (`MaterialApp`, tema, rotas). Nenhuma regra de negócio aqui.
- **`src/features/<feature>/`**: tudo que pertence a uma feature.
  - **`domain/`**: modelos/entidades e regras puras (sem Flutter/IO, quando possível).
  - **`data/`**: acesso a storage, rede, arquivos, plugins.
  - **`presentation/`**: telas/widgets + controle de estado.
- **`src/shared/`**: coisas reutilizáveis entre features (widgets, helpers). Evite colocar regra de negócio aqui.

## Fluxo de dependências (o que pode importar o quê)

- `presentation` → pode importar `domain` e `data`
- `data` → pode importar `domain`
- `domain` → não deve depender de `Flutter`, `IO`, `plugins` (ideal)
- `app` → orquestra as telas/features, mas não implementa regra de negócio

Se quiser ficar ainda mais "clean", o próximo passo seria trocar chamadas estáticas (`PackStorage.*`, `StickerManager.*`) por **interfaces + injeção** (ex.: via construtor), mas mantive o mínimo aqui para não quebrar o app.

## Como reaproveitar em outros projetos

1) Copie a pasta `lib/src/` inteira.
2) Renomeie `features/stickers` para sua feature (ex.: `features/auth`).
3) Em `src/app/app.dart`, troque o `home:` para sua página inicial.
4) Crie novas features duplicando o formato:

```
lib/src/features/minha_feature/
  data/
  domain/
  presentation/
```

## Testabilidade

- O `StickerApp` aceita `loadHomePacks: false` para permitir testes de widget sem inicializar plugins no `initState`.
- Para projetos maiores: prefira **injeção de dependências** para storage/serviços, evitando `static` em produção.
