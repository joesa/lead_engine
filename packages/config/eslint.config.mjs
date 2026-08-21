import { defineConfig, globalIgnores } from "eslint/config";

const commonIgnores = [
  "node_modules/**",
  "dist/**",
  ".next/**",
  "out/**",
  "build/**",
  "coverage/**",
  "*.min.js",
  "public/widget.js",
];

export function createConfig(overrides = {}) {
  return defineConfig([
    globalIgnores(commonIgnores),
    {
      languageOptions: {
        ecmaVersion: "latest",
        sourceType: "module",
      },
      rules: {
        "no-console": "warn",
        "no-debugger": "error",
        "prefer-const": "error",
        "no-var": "error",
        "eqeqeq": ["error", "always"],
        "curly": ["error", "all"],
        "@typescript-eslint/no-explicit-any": "warn",
        "@typescript-eslint/no-unused-vars": [
          "warn",
          {
            argsIgnorePattern: "^_",
            caughtErrorsIgnorePattern: "^_",
            destructuredArrayIgnorePattern: "^_",
            varsIgnorePattern: "^_",
          },
        ],
      },
    },
    overrides,
  ]);
}

export default createConfig();
