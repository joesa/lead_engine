import { z } from "zod";

export const publicEnvSchema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.string().url(),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1),
  NEXT_PUBLIC_SITE_URL: z.string().url().default("http://localhost:3000"),
  NEXT_PUBLIC_APP_URL: z.string().url().optional(),
  NEXT_PUBLIC_WIDGET_CDN_URL: z
    .string()
    .url()
    .default("https://closet-widget.vercel.app/loader.js"),
  NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY: z.string().optional(),
  NEXT_PUBLIC_DEMO_CONTRACTOR_ID: z.string().optional(),
  NEXT_PUBLIC_DEMO_ALLOWED_ORIGINS: z.string().optional(),
  NEXT_PUBLIC_SENTRY_DSN: z.string().optional(),
  NEXT_PUBLIC_TURNSTILE_SITE_KEY: z.string().optional(),
});

export const serverEnvSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1),
  DATABASE_URL: z.string().url().optional(),
  RESEND_API_KEY: z.string().optional(),
  TWILIO_ACCOUNT_SID: z.string().optional(),
  TWILIO_AUTH_TOKEN: z.string().optional(),
  TWILIO_PHONE_NUMBER: z.string().optional(),
  STRIPE_SECRET_KEY: z.string().optional(),
  STRIPE_WEBHOOK_SECRET: z.string().optional(),
  GEMINI_API_KEY: z.string().optional(),
  OPENAI_API_KEY: z.string().optional(),
  ANTHROPIC_API_KEY: z.string().optional(),
  SENTRY_DSN: z.string().optional(),
  CRON_SECRET: z.string().optional(),
  ADMIN_BYPASS_SECRET: z.string().optional(),
  REVALIDATE_SECRET: z.string().optional(),
  AI_CONFIG_KEY: z.string().optional(),
});

export type PublicEnv = z.infer<typeof publicEnvSchema>;
export type ServerEnv = z.infer<typeof serverEnvSchema>;

function getClientEnv() {
  const result = publicEnvSchema.safeParse({
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    NEXT_PUBLIC_SITE_URL: process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000",
    NEXT_PUBLIC_APP_URL: process.env.NEXT_PUBLIC_APP_URL,
    NEXT_PUBLIC_WIDGET_CDN_URL:
      process.env.NEXT_PUBLIC_WIDGET_CDN_URL ||
      "https://closet-widget.vercel.app/loader.js",
    NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY:
      process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY,
    NEXT_PUBLIC_DEMO_CONTRACTOR_ID: process.env.NEXT_PUBLIC_DEMO_CONTRACTOR_ID,
    NEXT_PUBLIC_DEMO_ALLOWED_ORIGINS: process.env.NEXT_PUBLIC_DEMO_ALLOWED_ORIGINS,
    NEXT_PUBLIC_SENTRY_DSN: process.env.NEXT_PUBLIC_SENTRY_DSN,
    NEXT_PUBLIC_TURNSTILE_SITE_KEY: process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY,
  });
  return result;
}

function getServerEnv() {
  const result = serverEnvSchema.safeParse({
    NODE_ENV: process.env.NODE_ENV,
    SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
    DATABASE_URL: process.env.DATABASE_URL,
    RESEND_API_KEY: process.env.RESEND_API_KEY,
    TWILIO_ACCOUNT_SID: process.env.TWILIO_ACCOUNT_SID,
    TWILIO_AUTH_TOKEN: process.env.TWILIO_AUTH_TOKEN,
    TWILIO_PHONE_NUMBER: process.env.TWILIO_PHONE_NUMBER,
    STRIPE_SECRET_KEY: process.env.STRIPE_SECRET_KEY,
    STRIPE_WEBHOOK_SECRET: process.env.STRIPE_WEBHOOK_SECRET,
    GEMINI_API_KEY: process.env.GEMINI_API_KEY,
    OPENAI_API_KEY: process.env.OPENAI_API_KEY,
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
    SENTRY_DSN: process.env.SENTRY_DSN,
    CRON_SECRET: process.env.CRON_SECRET,
    ADMIN_BYPASS_SECRET: process.env.ADMIN_BYPASS_SECRET,
    REVALIDATE_SECRET: process.env.REVALIDATE_SECRET,
    AI_CONFIG_KEY: process.env.AI_CONFIG_KEY,
  });
  return result;
}

export function validateClientEnv(): PublicEnv {
  const result = getClientEnv();
  if (!result.success) {
    if (process.env.NODE_ENV === "development") {
      console.warn(
        "[env] Client env validation issues:",
        result.error.errors.map((e) => `${e.path.join(".")}: ${e.message}`).join(", ")
      );
    }
  }
  return result.success ? result.data : ({} as PublicEnv);
}

export function validateServerEnv(): ServerEnv {
  const result = getServerEnv();
  if (!result.success) {
    const errors = result.error.errors.map(
      (e) => `${e.path.join(".")}: ${e.message}`
    );
    throw new Error(
      `[env] Server environment validation failed:\n${errors.join("\n")}`
    );
  }
  return result.data;
}

export function getPublicEnv(): PublicEnv {
  return validateClientEnv();
}

export function getPrivateEnv(): ServerEnv {
  return validateServerEnv();
}
