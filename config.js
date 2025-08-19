// === Supabase Frontend sozlamalari ===
// Bu ikkisini Supabase Dashboard → Settings → API bo‘limidan olasiz:

// 1) Project URL (aniq shu ko‘rinishda bo‘lishi kerak: https://xxxxx.supabase.co)
window.SUPABASE_URL = "https://eulfjekrjdtprffszxcf.supabase.co/functions/v1/tutor";

// 2) anon public key (service_role EMAS!)
window.SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV1bGZqZWtyamR0cHJmZnN6eGNmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTU2MzE4NjgsImV4cCI6MjA3MTIwNzg2OH0.TFjqVweIZWg3xAjA45wExOzFZ10DplSO3TzZmvUlLGo";

// (ixtiyoriy) Diagnostika uchun brauzer konsolida ko‘rish:
console.log("[config.js] SUPABASE_URL:", window.SUPABASE_URL);
console.log("[config.js] ANON_KEY mavjud:", !!window.SUPABASE_ANON_KEY);