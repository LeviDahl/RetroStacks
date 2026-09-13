import Foundation

/// The user's Supabase project (created 2026-09-12) — collection sync only, per
/// `supabase/README.md` / `supabase/schema.sql`. The catalog feed is unrelated
/// (`BackendConfig`) and doesn't touch this project.
///
/// The anon/publishable key is safe to ship: Postgres Row-Level Security (see
/// `schema.sql`) is what actually scopes access to `auth.uid()`, not secrecy of
/// this key — that's the whole point of a publishable key.
nonisolated enum SupabaseConfig {
    static let projectURL = URL(string: "https://vethkqrlcacmlffuzlnx.supabase.co")!
    static let anonKey = "sb_publishable_jJEKk7jnVq6rRjgwAP5yOQ_P3fi4WCz"

    static var authURL: URL { projectURL.appending(path: "auth/v1") }
    static var restURL: URL { projectURL.appending(path: "rest/v1") }
}
