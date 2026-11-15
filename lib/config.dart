/// Configuração do Supabase.
///
/// Preenche com os valores do teu projeto (Supabase → Project Settings → API).
/// A chave "anon"/"publishable" é pública por natureza: os dados ficam
/// protegidos pelas regras RLS definidas em `supabase/schema.sql`.
///
/// Se ficarem vazios, a app funciona só em modo local (sem sincronização).
/// Também podem ser passados na compilação:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
const supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: '',
);

bool get supabaseConfigured =>
    supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
