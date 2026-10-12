/// Konfigurasi Supabase diisi saat build/run:
/// flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_KEY=xxx
///
/// SUPABASE_KEY = "Publishable key" (atau "anon key" lama) dari
/// Supabase Dashboard > Project Settings > API Keys. Jangan pakai service_role key.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_KEY');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
