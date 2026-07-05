# PocketBase Flutter Android

App Android (Flutter) que executa o **PocketBase oficial pré-compilado** como
servidor local embutido — sem gomobile, sem restrições de tipos, sempre na
última versão.

## Como funciona

```
┌─────────────────────────────────────────────┐
│                  APK (Flutter)               │
│                                              │
│  ┌──────────┐     ┌──────────────────────┐  │
│  │  Dart UI │────▶│  dart:io Process     │  │
│  │  (Flutter)│    │  .start(libpocketbase│  │
│  └────┬─────┘     │       .so serve ...) │  │
│       │           └──────────┬───────────┘  │
│       │ HTTP localhost:8090  │              │
│       └──────────────────────┼──────────────┘
│                              ▼               │
│  ┌──────────────────────────────────────┐   │
│  │  libpocketbase.so (binário oficial)  │   │
│  │  • arm64-v8a   (linux_arm64)         │   │
│  │  • armeabi-v7a (linux_armv7)         │   │
│  │  • x86_64      (linux_amd64)         │   │
│  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

### Por que este approach?

1. **Sem gomobile** — o binário é o PocketBase completo, sem restrições de
   tipos da ponte JNI do gomobile.
2. **Sempre na versão mais recente** — o CI baixa o release oficial mais
   recente de https://github.com/pocketbase/pocketbase/releases.
3. **Sem compilação Go** — o build é só Flutter + download de binário.
   Tempo de CI: ~5 min.

### Por que funciona no Android?

O PocketBase publica binários **estáticos** (puro Go, `CGO_ENABLED=0`, sem
glibc). O kernel do Android é Linux, então qualquer ELF estático roda
nativamente. A única restrição é a regra W^X do Android 10+ que proíbe
`exec()` a partir do diretório gravável do app — mas arquivos enviados
dentro do APK em `lib/<abi>/` e nomeados `lib*.so` são extraídos para
`/data/app/<pkg>/lib/<abi>/` com permissão de execução, e podem ser
executados via `Process.start()`.

## Build

O workflow `.github/workflows/build.yml` faz:

1. Resolve a versão mais recente do PocketBase via GitHub API.
2. Baixa os binários `linux_arm64`, `linux_armv7`, `linux_amd64`.
3. Renomeia cada um para `libpocketbase.so` e coloca em
   `android/app/src/main/jniLibs/<abi>/`.
4. Executa `flutter build apk --release`.
5. Faz upload do APK como artifact.

## Desenvolvimento local

Como os binários `libpocketbase.so` são baixados pelo CI, para rodar
localmente você precisa baixá-los manualmente:

```bash
LATEST=$(curl -s https://api.github.com/repos/pocketbase/pocketbase/releases/latest | jq -r .tag_name)
NUM=${LATEST#v}
JNILIBS=android/app/src/main/jniLibs
mkdir -p $JNILIBS/{arm64-v8a,armeabi-v7a,x86_64}

for pair in "arm64:arm64-v8a" "armv7:armeabi-v7a" "amd64:x86_64"; do
  arch=${pair%%:*}; abi=${pair##*:}
  curl -fL "https://github.com/pocketbase/pocketbase/releases/download/$LATEST/pocketbase_${NUM}_linux_${arch}.zip" -o pb.zip
  unzip -o pb.zip pocketbase
  mv pocketbase "$JNILIBS/$abi/libpocketbase.so"
done
```

Depois: `flutter pub get && flutter run` (ou `flutter build apk`).
