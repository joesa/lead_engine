import { createClient } from "@supabase/supabase-js";

const DEDUP_WINDOW_MS = 5 * 60 * 1000;

export interface DedupeEntry {
  id: string;
  key: string;
  processed_at: string;
  created_at: string;
}

export interface DedupeOptions {
  windowMs?: number;
  tableName?: string;
}

export function hashRequest(request: Request | { url: string; body?: unknown; headers?: Record<string, string> }): string {
  const data = {
    url: request.url,
    body: typeof request.clone === "function" ? undefined : request.body,
    headers: Object.fromEntries(
      request.headers instanceof Headers
        ? request.headers.entries()
        : Object.entries(request.headers || {})
    ),
  };
  
  if (typeof request.clone === "function" && request.body) {
    return request.url;
  }
  
  const str = JSON.stringify(data);
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = (hash << 5) - hash + char;
    hash = hash & hash;
  }
  return Math.abs(hash).toString(36);
}

export class WebhookDeduplicator {
  private supabase: ReturnType<typeof createClient> | null = null;
  private tableName: string;
  private windowMs: number;
  private localCache = new Map<string, number>();

  constructor(
    supabaseUrl?: string,
    supabaseKey?: string,
    options: DedupeOptions = {}
  ) {
    this.tableName = options.tableName || "webhook_dedupe";
    this.windowMs = options.windowMs || DEDUP_WINDOW_MS;

    if (supabaseUrl && supabaseKey) {
      this.supabase = createClient(supabaseUrl, supabaseKey);
    }
  }

  async isDuplicate(key: string): Promise<boolean> {
    if (typeof window !== "undefined") {
      const cached = this.localCache.get(key);
      if (cached && Date.now() - cached < this.windowMs) {
        return true;
      }
      this.localCache.set(key, Date.now());
      return false;
    }

    if (!this.supabase) {
      const cached = this.localCache.get(key);
      if (cached && Date.now() - cached < this.windowMs) {
        return true;
      }
      this.localCache.set(key, Date.now());
      return false;
    }

    const cutoff = new Date(Date.now() - this.windowMs).toISOString();

    const { data, error } = await this.supabase
      .from(this.tableName)
      .select("id")
      .eq("dedupe_key", key)
      .gt("created_at", cutoff)
      .limit(1);

    if (error) {
      console.error("[dedupe] Error checking duplicate:", error);
      return false;
    }

    if (data && data.length > 0) {
      return true;
    }

    return false;
  }

  async markProcessed(key: string): Promise<void> {
    this.localCache.set(key, Date.now());

    if (!this.supabase) {
      return;
    }

    const { error } = await this.supabase
      .from(this.tableName)
      .insert({ dedupe_key: key });

    if (error) {
      console.error("[dedupe] Error marking as processed:", error);
    }
  }

  async cleanup(): Promise<number> {
    if (!this.supabase) {
      let cleaned = 0;
      const now = Date.now();
      for (const [key, timestamp] of this.localCache.entries()) {
        if (now - timestamp > this.windowMs) {
          this.localCache.delete(key);
          cleaned++;
        }
      }
      return cleaned;
    }

    const cutoff = new Date(Date.now() - this.windowMs).toISOString();

    const { count, error } = await this.supabase
      .from(this.tableName)
      .delete()
      .lt("created_at", cutoff)
      .select("id", { count: "exact" });

    if (error) {
      console.error("[dedupe] Error during cleanup:", error);
      return 0;
    }

    return count || 0;
  }

  clearLocalCache(): void {
    this.localCache.clear();
  }
}

export function createWebhookDeduplicator(
  supabaseUrl?: string,
  supabaseKey?: string,
  options?: DedupeOptions
) {
  return new WebhookDeduplicator(supabaseUrl, supabaseKey, options);
}

export async function withDeduplication<T>(
  deduplicator: WebhookDeduplicator,
  key: string,
  fn: () => Promise<T>
): Promise<{ success: boolean; result?: T; duplicate?: boolean }> {
  const isDuplicate = await deduplicator.isDuplicate(key);

  if (isDuplicate) {
    return { success: true, duplicate: true };
  }

  try {
    const result = await fn();
    await deduplicator.markProcessed(key);
    return { success: true, result };
  } catch (error) {
    return { success: false, duplicate: false };
  }
}
