# Agenda

App de calendário e tarefas para **Windows** e **Android**, feita em Flutter,
com sincronização através do Supabase.

- **Calendário** e **Tarefas** são duas áreas separadas da mesma app.
- Funciona offline: tudo é gravado no dispositivo e enviado quando há rede.
- As alterações aparecem no outro dispositivo em tempo real.

## 1. Preparar o Supabase (uma vez)

1. Cria um projeto gratuito em <https://supabase.com>.
2. Em **SQL Editor**, cola e corre o conteúdo de [`supabase/schema.sql`](supabase/schema.sql).
3. Em **Project Settings → API**, copia o **Project URL** e a chave **anon / publishable**.
4. (Opcional) Em **Authentication → Sign In / Providers → Email**, desliga
   "Confirm email" para poderes criar a conta diretamente na app. Em
   alternativa, cria o utilizador em **Authentication → Users → Add user**.

## 2. Correr / compilar

É preciso o [Flutter](https://docs.flutter.dev/get-started/install). Para
Windows é também preciso o Visual Studio com "Desktop development with C++";
para Android, o Android Studio.

Os dados do Supabase passam-se na compilação (ou escrevem-se em `lib/config.dart`):

```bash
flutter run -d windows --dart-define=SUPABASE_URL=https://XXXX.supabase.co --dart-define=SUPABASE_ANON_KEY=XXXX
```

```bash
flutter build windows --release --dart-define=SUPABASE_URL=https://XXXX.supabase.co --dart-define=SUPABASE_ANON_KEY=XXXX
```

```bash
flutter build apk --release --dart-define=SUPABASE_URL=https://XXXX.supabase.co --dart-define=SUPABASE_ANON_KEY=XXXX
```

- Windows: o resultado fica em `build/windows/x64/runner/Release/` (copia a pasta inteira).
- Android: `build/app/outputs/flutter-apk/app-release.apk` (instala no telemóvel).

Sem estes valores a app arranca em **modo local** (sem conta nem sincronização),
útil para experimentar.

Em alternativa a compilar no teu PC, o workflow `.github/workflows/build.yml`
compila ambas as versões no GitHub Actions.

## Como funciona a sincronização

- Cada alteração é gravada localmente e marcada como pendente.
- Ao sincronizar, a app descarrega o estado do servidor, funde-o com o local
  e envia as alterações pendentes. Em conflito ganha a alteração mais recente.
- Eliminações são lógicas (`deleted_at`) para se propagarem; são limpas ao fim de 30 dias.
- O ícone da nuvem no canto superior direito mostra o estado; tocar força a sincronização.

## Estrutura

| Ficheiro | Conteúdo |
| --- | --- |
| `lib/models.dart` | `Event` e `Task` |
| `lib/store.dart` | Dados locais + algoritmo de sincronização |
| `lib/supabase_sync.dart` | Ligação ao Supabase (sessão, tempo real) |
| `lib/screens/` | Ecrãs: login, calendário, tarefas, editores |
| `supabase/schema.sql` | Tabelas e regras de segurança |
| `test/` | Testes da sincronização (`flutter test`) |
