// =====================================================================
// _core.js — Supabase mijozi (barcha firebase-* shimlar shu bitta mijozdan foydalanadi).
// =====================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

let _sb = null;
export function initSupabase(url, anonKey) { _sb = createClient(url, anonKey); return _sb; }
export function supabase() { return _sb; }
export function _setClient(c) { _sb = c; }   // faqat sinov uchun (soxta mijoz inject)
