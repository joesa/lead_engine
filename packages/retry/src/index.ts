import { retry as pRetry, Options as RetryOptions } from "p-retry";

export { pRetry };

export interface CircuitBreakerOptions {
  failureThreshold?: number;
  successThreshold?: number;
  timeout?: number;
}

export class CircuitBreaker {
  private failures = 0;
  private successes = 0;
  private state: "closed" | "open" | "half-open" = "closed";
  private lastFailureTime = 0;
  private readonly failureThreshold: number;
  private readonly successThreshold: number;
  private readonly timeout: number;

  constructor(options: CircuitBreakerOptions = {}) {
    this.failureThreshold = options.failureThreshold ?? 5;
    this.successThreshold = options.successThreshold ?? 2;
    this.timeout = options.timeout ?? 60000;
  }

  async execute<T>(fn: () => Promise<T>): Promise<T> {
    if (this.state === "open") {
      if (Date.now() - this.lastFailureTime >= this.timeout) {
        this.state = "half-open";
      } else {
        throw new Error("Circuit breaker is open");
      }
    }

    try {
      const result = await fn();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }

  private onSuccess() {
    this.failures = 0;
    if (this.state === "half-open") {
      this.successes++;
      if (this.successes >= this.successThreshold) {
        this.state = "closed";
        this.successes = 0;
      }
    }
  }

  private onFailure() {
    this.failures++;
    this.lastFailureTime = Date.now();
    if (this.state === "half-open" || this.failures >= this.failureThreshold) {
      this.state = "open";
    }
  }

  getState() {
    return this.state;
  }

  reset() {
    this.failures = 0;
    this.successes = 0;
    this.state = "closed";
  }
}

export const defaultRetryOptions: RetryOptions = {
  retries: 3,
  backoff: {
    type: "exponential",
    factor: 2,
  },
  onFailedAttempt: (error) => {
    console.warn(`Retry attempt failed: ${error.message}`);
  },
};

export async function withRetry<T>(
  fn: () => Promise<T>,
  options: RetryOptions = {}
): Promise<T> {
  return pRetry(fn, { ...defaultRetryOptions, ...options });
}

export function createCircuitBreaker(options?: CircuitBreakerOptions) {
  return new CircuitBreaker(options);
}

const circuitBreakers = new Map<string, CircuitBreaker>();

export function getCircuitBreaker(name: string, options?: CircuitBreakerOptions) {
  if (!circuitBreakers.has(name)) {
    circuitBreakers.set(name, new CircuitBreaker(options));
  }
  return circuitBreakers.get(name)!;
}
