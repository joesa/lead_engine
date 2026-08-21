import { z } from "zod";

export const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1, "Required for server-side operations"),
  NEXT_PUBLIC_SUPABASE_URL: z.string().url(),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1),
  DATABASE_URL: z.string().url().optional(),
  RESEND_API_KEY: z.string().optional(),
  TWILIO_ACCOUNT_SID: z.string().optional(),
  TWILIO_AUTH_TOKEN: z.string().optional(),
  TWILIO_PHONE_NUMBER: z.string().optional(),
  TWILIO_WEBHOOK_URL: z.string().url().optional(),
  SMS_MAX_DAILY: z.coerce.number().int().positive().default(50),
  SMS_STEP2_DELAY_DAYS: z.coerce.number().int().positive().default(2),
  SMS_SEND_WINDOW_ENFORCE: z
    .string()
    .transform((v) => v === "true")
    .default("true"),
  OUTREACH_LOOM_URL: z.string().url().optional(),
  OUTREACH_LANDING_URL: z.string().url().default("https://www.ditchtheform.com/#demo"),
  STRIPE_SECRET_KEY: z.string().optional(),
  STRIPE_WEBHOOK_SECRET: z.string().optional(),
  NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY: z.string().optional(),
  STRIPE_PRICE_MONTHLY: z.string().optional(),
  STRIPE_PRICE_YEARLY: z.string().optional(),
  NEXT_PUBLIC_SITE_URL: z.string().url().default("http://localhost:3000"),
  NEXT_PUBLIC_APP_URL: z.string().url().optional(),
  NEXT_PUBLIC_WIDGET_CDN_URL: z
    .string()
    .url()
    .default("https://closet-widget.vercel.app/loader.js"),
  ADMIN_BYPASS_SECRET: z.string().optional(),
  REVALIDATE_SECRET: z.string().optional(),
  SENTRY_DSN: z.string().optional(),
  NEXT_PUBLIC_SENTRY_DSN: z.string().optional(),
  GEMINI_API_KEY: z.string().optional(),
  CUSTOM_SITE_GEMINI_MODEL: z.string().optional(),
  FULL_REDESIGN_GEMINI_MODEL: z.string().optional(),
  FIRECRAWL_API_KEY: z.string().optional(),
  FIRECRAWL_API_URL: z.string().url().optional(),
  AI_CONFIG_KEY: z.string().optional(),
  ANTHROPIC_API_KEY: z.string().optional(),
  CUSTOM_SITE_CLAUDE_MODEL: z.string().optional(),
  FULL_REDESIGN_ANTHROPIC_MODEL: z.string().optional(),
  OPENAI_API_KEY: z.string().optional(),
  CUSTOM_SITE_OPENAI_MODEL: z.string().optional(),
  FULL_REDESIGN_OPENAI_MODEL: z.string().optional(),
  DEMO_CONTRACTOR_ID: z.string().optional(),
  NEXT_PUBLIC_DEMO_CONTRACTOR_ID: z.string().optional(),
  DEMO_ALLOWED_ORIGINS: z.string().optional(),
  NEXT_PUBLIC_DEMO_ALLOWED_ORIGINS: z.string().optional(),
  CRON_SECRET: z.string().optional(),
  PROVISION_BATCH_SIZE: z.coerce.number().int().positive().default(5),
  PROVISION_MAX_ATTEMPTS: z.coerce.number().int().positive().default(3),
  AUTO_LAUNCH_REDESIGN: z
    .string()
    .transform((v) => v === "true")
    .default("true"),
  TURNSTILE_SECRET: z.string().optional(),
  TURNSTILE_SECRET_KEY: z.string().optional(),
  NEXT_PUBLIC_TURNSTILE_SITE_KEY: z.string().optional(),
  INTAKE_FROM_EMAIL: z.string().email().optional(),
  INTAKE_TIER_STANDARD_CENTS: z.coerce.number().int().positive().default(129900),
  INTAKE_TIER_AI_PREMIUM_CENTS: z.coerce.number().int().positive().default(249900),
  INTAKE_AI_MAX_ATTEMPTS_PER_SLOT: z.coerce.number().int().positive().default(3),
  SITE_MAINTENANCE_MONTHLY_CENTS: z.coerce.number().int().positive().default(11900),
  SITE_MAINTENANCE_YEARLY_CENTS: z.coerce.number().int().positive().default(119000),
  WIDGET_SUBSCRIPTION_MONTHLY_CENTS: z.coerce.number().int().positive().default(9900),
  WIDGET_SUBSCRIPTION_YEARLY_CENTS: z.coerce.number().int().positive().default(99000),
  SCRAPER_TRIGGER_WEBHOOK_URL: z.string().url().optional(),
  SCRAPER_TRIGGER_WEBHOOK_TOKEN: z.string().optional(),
  SCRAPER_LOCAL_DIR: z.string().optional(),
  SCRAPER_LOCAL_RUN_COMMAND: z.string().optional(),
  INSTANTLY_RECEIVER_AUTH_TOKEN: z.string().optional(),
  INSTANTLY_WEBHOOK_SECRET: z.string().optional(),
  SCRAPER_CONTROL_PLANE_TOKEN: z.string().optional(),
  INSTANTLY_MIN_LEADS_PER_BATCH: z.coerce.number().int().nonnegative().default(1),
  INSTANTLY_WARMUP_MODE: z
    .string()
    .transform((v) => v === "true")
    .default("true"),
  INSTANTLY_AUTO_START: z
    .string()
    .transform((v) => v === "true")
    .default("false"),
  INSTANTLY_API_KEY: z.string().optional(),
  INSTANTLY_API_BASE_URL: z
    .string()
    .url()
    .default("https://api.instantly.ai/api/v2"),
  SPEC_BUILD_ENABLED: z
    .string()
    .transform((v) => v === "true")
    .default("false"),
  SPEC_BUILD_DAILY_MAX: z.coerce.number().int().positive().default(5),
  SPEC_BUILD_MAX_IN_FLIGHT: z.coerce.number().int().positive().default(2),
  SPEC_BUILD_MAX_SERVICES: z.coerce.number().int().positive().default(5),
  SPEC_BUILD_IMAGE_VARIANTS: z.coerce.number().int().positive().default(1),
  SPEC_PLACEHOLDER_EMAIL_DOMAIN: z.string().default("ditchtheform.com"),
  SPEC_PREVIEW_SECRET: z.string().optional(),
  SPEC_OFFER_DISCOUNT_BPS: z.coerce.number().int().nonnegative().default(5000),
  SPEC_OFFER_DEADLINE_HOURS: z.coerce.number().int().positive().default(168),
  SPEC_OFFER_REMINDER_HOURS: z.coerce.number().int().positive().default(24),
  SPEC_PURGE_GRACE_HOURS: z.coerce.number().int().positive().default(24),
  SPEC_BUILD_SMS_ALLOWLIST: z.string().optional(),
});

export type Env = z.infer<typeof envSchema>;

export function validateEnv(): Env {
  const result = envSchema.safeParse(process.env);
  if (!result.success) {
    const errors = result.error.errors.map(
      (e) => `${e.path.join(".")}: ${e.message}`
    );
    throw new Error(`Environment validation failed:\n${errors.join("\n")}`);
  }
  return result.data;
}

export function getEnv(): Env {
  return validateEnv();
}
