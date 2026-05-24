AppDeFigurinhas

Aplicativo Flutter para criar e organizar figurinhas (stickers) com editor de texto simples.

Visão geral

Este projeto é um protótipo de aplicativo Flutter que permite criar pacotes de figurinhas, adicionar imagens e editá-las com sobreposição de texto. O app recebeu um redesign "Clean Light" com fontes via google_fonts, além de uma tela de introdução (splash) e um fluxo sequencial de edição de imagens ao adicionar novas figurinhas.

Funcionalidades principais:
- Tema moderno "Clean Light" (Material 3)
- Tela de introdução (IntroPage)
- Fluxo para criar pacotes de figurinhas e adicionar imagens
- Editor de imagem simples: adicionar texto, arrastar texto sobre a imagem, salvar cópia editada
- As imagens editadas são salvas em uma pasta local `edited_stickers` dentro do diretório de documentos do app

Estrutura importante

- `lib/src/app/app.dart` — entrada do aplicativo, título e navegação inicial
- `lib/src/app/theme/app_theme.dart` — tema e estilos da aplicação
- `lib/src/features/onboarding/presentation/intro_page.dart` — tela de introdução
- `lib/src/features/stickers/presentation/home_page.dart` — tela principal e fluxo de pacotes/figurinhas
- `lib/src/features/stickers/presentation/editor/sticker_image_editor_page.dart` — editor de imagem (texto sobre imagem)

Dependências relevantes

As dependências chave adicionadas/alteradas durante o desenvolvimento:
- `google_fonts` — usada para aplicar fontes (ex.: Manrope)
- `http` — versão atualizada para compatibilidade com `google_fonts` (ex.: `^1.6.0`)

Verifique `pubspec.yaml` para a lista completa de pacotes e versões.

Como rodar

Pré-requisitos:
- Flutter SDK (versão compatível com o projeto, por exemplo Dart 3.x)
- Dispositivo/emulador configurado ou `flutter run` apontando para um dispositivo

Comandos básicos:

```
cd flutter_application_1
flutter pub get
flutter run
```

Onde são salvas as imagens editadas

As imagens geradas pelo editor são escritas em tempo de execução no diretório de documentos do app, na subpasta `edited_stickers`. Em Android/iOS esse diretório é provido por `path_provider`.

Notas de desenvolvimento

- O editor usa `RepaintBoundary` + `toImage` para capturar a composição atual (imagem + sobreposições) e salvar em PNG.
- A implementação atual suporta apenas texto como recurso de edição (arrastar, alterar tamanho por slider, mudar cor através de paleta simples).
- Melhorias futuras sugeridas: seleção de fontes, paleta de cores avançada, inserir texto diretamente sobre a imagem com ações rápidas, redimensionamento por gesto (pinch-to-zoom) e integração com `flutter_launcher_icons` para configurar o ícone do app.

Alterar nome do app e ícone

- Android: `android/app/src/main/AndroidManifest.xml` (atributo `android:label`) foi atualizado para `AppDeFigurinhas`.
- iOS: `ios/Runner/Info.plist` (CFBundleName / CFBundleDisplayName) foi atualizado para `AppDeFigurinhas`.
- Para ajustar o ícone, recomendo usar `flutter_launcher_icons` (adicione ao `dev_dependencies` e configure no `pubspec.yaml`).

Contato

Se precisar que eu adicione o README em outro local, traduções, ou inclua instruções específicas (por exemplo, CI/CD, testes), me avise.

---
Gerado automaticamente pelo assistente em maio de 2026.
# flutter_application_1

A new Flutter project.

## Arquitetura

See [ARCHITECTURE.md](ARCHITECTURE.md) for the reusable project architecture and folder conventions.

See [PROJECT_BLUEPRINT.md](PROJECT_BLUEPRINT.md) for stack, language/SDK, system design, and reuse checklist.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
