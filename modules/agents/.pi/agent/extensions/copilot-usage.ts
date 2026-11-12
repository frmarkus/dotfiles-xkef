import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

const STATUS_KEY = "copilot-usage";
const API_TIMEOUT_MS = 5_000;
const POLL_INTERVAL_MS = 15_000;
const COPILOT_PROVIDER = "github-copilot";
const CODEX_PROVIDER = "openai-codex";
const OPENROUTER_PROVIDER = "openrouter";
const CODEX_USAGE_URL = "https://chatgpt.com/backend-api/wham/usage";
const COPILOT_USAGE_URL = "https://api.github.com/copilot_internal/user";
const OPENROUTER_KEY_URL = "https://openrouter.ai/api/v1/key";
const CODEX_AUTH_CLAIM = "https://api.openai.com/auth";
const FULL_PERCENT = 100;
const SECONDS_PER_MINUTE = 60;
const SECONDS_PER_HOUR = 3_600;
const SECONDS_PER_DAY = 86_400;
const format = new Intl.NumberFormat("en-US");
const dollars = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
});

type Usage = {
  used: number;
  total: number;
};

type UsageStatus = {
  text: string;
  percent: number;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function numberField(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function parseUsage(value: unknown): Usage | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  const snapshots = value.quota_snapshots;
  if (!isRecord(snapshots)) {
    return undefined;
  }

  const quota = snapshots.premium_interactions;
  if (!isRecord(quota)) {
    return undefined;
  }

  const total = numberField(quota.entitlement);
  if (total === undefined || total <= 0) {
    return undefined;
  }

  const remaining = numberField(quota.quota_remaining) ?? numberField(quota.remaining);
  const used = numberField(quota.credits_used) ?? (remaining === undefined ? undefined : total - remaining);
  if (used === undefined) {
    return undefined;
  }

  return {
    used: Math.max(0, Math.round(used)),
    total: Math.round(total),
  };
}

async function readOAuthToken(): Promise<string | undefined> {
  const agentDir = process.env.PI_CODING_AGENT_DIR ?? join(homedir(), ".pi", "agent");
  const value: unknown = JSON.parse(await readFile(join(agentDir, "auth.json"), "utf8"));
  if (!isRecord(value)) {
    return undefined;
  }

  const credential = value[COPILOT_PROVIDER];
  if (!isRecord(credential) || credential.type !== "oauth") {
    return undefined;
  }

  return typeof credential.refresh === "string" ? credential.refresh : undefined;
}

function isOffline(): boolean {
  return ["1", "true", "yes"].includes((process.env.PI_OFFLINE ?? "").toLowerCase());
}

function formatWindow(seconds: number): string {
  if (seconds % SECONDS_PER_DAY === 0) {
    return `${seconds / SECONDS_PER_DAY}d`;
  }
  if (seconds % SECONDS_PER_HOUR === 0) {
    return `${seconds / SECONDS_PER_HOUR}h`;
  }
  return `${format.format(seconds / SECONDS_PER_MINUTE)}m`;
}

function parseCodexUsage(value: unknown): UsageStatus | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  const windows: string[] = [];
  let percent = 0;
  if (isRecord(value.rate_limit)) {
    for (const window of [value.rate_limit.primary_window, value.rate_limit.secondary_window]) {
      if (!isRecord(window)) {
        continue;
      }
      const used = numberField(window.used_percent);
      const seconds = numberField(window.limit_window_seconds);
      if (used === undefined || seconds === undefined || seconds <= 0) {
        continue;
      }

      const clamped = Math.max(0, Math.min(FULL_PERCENT, used));
      percent = Math.max(percent, clamped);
      windows.push(`${formatWindow(seconds)} ${format.format(FULL_PERCENT - clamped)}%`);
    }
  }

  const parts = windows.length ? [`${windows.join(" / ")} left`] : [];
  if (isRecord(value.credits)) {
    const credits = value.credits;
    const balance = typeof credits.balance === "string" && credits.balance.trim() !== ""
      ? numberField(Number(credits.balance))
      : numberField(credits.balance);
    if (credits.unlimited === true) {
      parts.push("unlimited credits");
    } else if (balance !== undefined) {
      parts.push(`${format.format(balance)} credits`);
    }
  }

  return parts.length ? { text: `OpenAI ${parts.join(" · ")}`, percent } : undefined;
}

function readAccountId(token: string): string | undefined {
  try {
    const payload: unknown = JSON.parse(Buffer.from(token.split(".")[1] ?? "", "base64url").toString());
    const claim = isRecord(payload) ? payload[CODEX_AUTH_CLAIM] : undefined;
    const accountId = isRecord(claim) ? claim.chatgpt_account_id : undefined;
    return typeof accountId === "string" && accountId.length > 0 ? accountId : undefined;
  } catch {
    return undefined;
  }
}

async function readCodexUsage(
  ctx: ExtensionContext,
  signal: AbortSignal,
): Promise<UsageStatus | undefined> {
  // Resolve through pi so expired subscription tokens refresh.
  const auth = (await ctx.modelRegistry.getProviderAuth(CODEX_PROVIDER))?.auth;
  if (!auth?.apiKey || signal.aborted) {
    return undefined;
  }
  const accountId = readAccountId(auth.apiKey);
  if (!accountId) {
    return undefined;
  }

  const response = await fetch(CODEX_USAGE_URL, {
    headers: {
      Authorization: `Bearer ${auth.apiKey}`,
      "ChatGPT-Account-Id": accountId,
      Accept: "application/json",
    },
    signal: AbortSignal.any([signal, AbortSignal.timeout(API_TIMEOUT_MS)]),
  });
  if (!response.ok) {
    return undefined;
  }
  return parseCodexUsage(await response.json());
}

async function readCopilotUsage(signal: AbortSignal): Promise<UsageStatus | undefined> {
  const token = await readOAuthToken();
  if (!token) {
    return undefined;
  }

  // Use pi's Copilot account instead of the active gh account.
  const response = await fetch(COPILOT_USAGE_URL, {
    headers: {
      Authorization: `token ${token}`,
      Accept: "application/json",
    },
    signal: AbortSignal.any([signal, AbortSignal.timeout(API_TIMEOUT_MS)]),
  });
  if (!response.ok) {
    return undefined;
  }
  const usage = parseUsage(await response.json());
  return usage ? {
    text: `Copilot ${format.format(usage.used)} / ${format.format(usage.total)} AI credits`,
    percent: (usage.used / usage.total) * FULL_PERCENT,
  } : undefined;
}

// OpenRouter reports the key's spend in dollars. The footer shows the
// session's own cost next to it. The key's limit_remaining is a per-key
// cap, not the account balance, and the balance endpoint needs a
// management key, so the footer shows no amount left.
function parseOpenRouterUsage(value: unknown): UsageStatus | undefined {
  if (!isRecord(value) || !isRecord(value.data)) {
    return undefined;
  }

  const key = value.data;
  const today = numberField(key.usage_daily);
  const month = numberField(key.usage_monthly);
  if (today === undefined || month === undefined) {
    return undefined;
  }

  return {
    text: `OpenRouter ${dollars.format(today)} today · ${dollars.format(month)} this month`,
    percent: 0,
  };
}

async function readOpenRouterUsage(
  ctx: ExtensionContext,
  signal: AbortSignal,
): Promise<UsageStatus | undefined> {
  const apiKey = await ctx.modelRegistry.getApiKeyForProvider(OPENROUTER_PROVIDER);
  if (!apiKey || signal.aborted) {
    return undefined;
  }

  const response = await fetch(OPENROUTER_KEY_URL, {
    headers: {
      Authorization: `Bearer ${apiKey}`,
      Accept: "application/json",
    },
    signal: AbortSignal.any([signal, AbortSignal.timeout(API_TIMEOUT_MS)]),
  });
  if (!response.ok) {
    return undefined;
  }
  return parseOpenRouterUsage(await response.json());
}

function showUsage(ctx: ExtensionContext, usage: UsageStatus | undefined): void {
  if (!usage) {
    ctx.ui.setStatus(STATUS_KEY, undefined);
    return;
  }

  const color = usage.percent > 90 ? "error" : usage.percent > 70 ? "warning" : "dim";
  ctx.ui.setStatus(STATUS_KEY, ctx.ui.theme.fg(color, usage.text));
}

export default function (pi: ExtensionAPI) {
  let active = false;
  let controller: AbortController | undefined;
  let pendingContext: ExtensionContext | undefined;
  let request: Promise<void> | undefined;
  let selectedProvider: string | undefined;
  let latestContext: ExtensionContext | undefined;
  let timer: ReturnType<typeof setInterval> | undefined;

  async function update(
    ctx: ExtensionContext,
    provider: string | undefined,
    signal: AbortSignal,
  ): Promise<void> {
    let usage: UsageStatus | undefined;
    if (provider === CODEX_PROVIDER) {
      usage = await readCodexUsage(ctx, signal);
    } else if (provider === COPILOT_PROVIDER) {
      usage = await readCopilotUsage(signal);
    } else if (provider === OPENROUTER_PROVIDER) {
      usage = await readOpenRouterUsage(ctx, signal);
    }

    if (active && !signal.aborted && selectedProvider === provider) {
      showUsage(ctx, usage);
    }
  }

  function refresh(ctx: ExtensionContext): void {
    const provider = ctx.model?.provider;
    if (selectedProvider !== provider) {
      selectedProvider = provider;
      ctx.ui.setStatus(STATUS_KEY, undefined);
      controller?.abort();
    }

    if (isOffline()) {
      return;
    }
    if (request) {
      pendingContext = ctx;
      return;
    }

    controller = new AbortController();
    const currentController = controller;
    request = update(ctx, provider, currentController.signal)
      .catch(() => {
        if (active && !currentController.signal.aborted && selectedProvider === provider) {
          ctx.ui.setStatus(STATUS_KEY, undefined);
        }
      })
      .finally(() => {
        request = undefined;
        if (controller === currentController) {
          controller = undefined;
        }

        const nextContext = pendingContext;
        pendingContext = undefined;
        if (active && nextContext) {
          refresh(nextContext);
        }
      });
  }

  function refreshLatest(ctx: ExtensionContext): void {
    latestContext = ctx;
    if (ctx.hasUI) {
      refresh(ctx);
    }
  }

  // Subagents spend on the same key without firing events here, and
  // OpenRouter books spend some seconds after a response, so the footer
  // also polls while the session runs.
  pi.on("session_start", async (_event, ctx) => {
    active = true;
    refreshLatest(ctx);
    clearInterval(timer);
    timer = setInterval(() => {
      if (latestContext) {
        refreshLatest(latestContext);
      }
    }, POLL_INTERVAL_MS);
    timer.unref();
  });

  pi.on("model_select", async (_event, ctx) => refreshLatest(ctx));
  pi.on("turn_end", async (_event, ctx) => refreshLatest(ctx));
  pi.on("agent_settled", async (_event, ctx) => refreshLatest(ctx));

  pi.on("session_shutdown", async () => {
    active = false;
    pendingContext = undefined;
    latestContext = undefined;
    clearInterval(timer);
    controller?.abort();
  });
}
