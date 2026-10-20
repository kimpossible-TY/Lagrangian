import globals from "globals";
import typescriptEslint from "@typescript-eslint/eslint-plugin";
import tsParser from "@typescript-eslint/parser";
import js from "@eslint/js";
import { FlatCompat } from "@eslint/eslintrc";

const compat = new FlatCompat({
  baseDirectory: import.meta.dirname,
  resolvePluginsRelativeTo: import.meta.dirname,
  recommendedConfig: js.configs.recommended,
  allConfig: js.configs.all,
});

export default [
  {
    ignores: [
      "**/.eslintrc.js",
      "**/out/",
      "**/node_modules/",
      "tools/flow-reader/web/vendor/**",
      "tools/typst-preview-frontend/dist/**",
      "tools/typst-dom/dist/**",
    ],
  },
  {
    files: ["editors/vscode/**/*.ts"],
    languageOptions: {
      globals: {
        ...globals.browser,
        ...globals.node,
      },
    },
  },
  {
    files: [
      "tools/reader-common/**/*.js",
      "tools/reader-common/**/*.mjs",
      "tools/flow-reader/web/**/*.js",
      "tools/flow-reader/terminal/**/*.mjs",
      "tools/flow-reader/terminal.mjs",
      "tools/flow-reader/tests/*.mjs",
      "tools/typst-preview-frontend/src/**/*.{ts,mts}",
      "tools/typst-dom/src/**/*.{ts,mts}",
    ],
    ignores: ["**/vendor/**", "**/*.d.ts"],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: globals.browser,
    },
    rules: {
      ...js.configs.recommended.rules,
      "no-unused-vars": ["error", { args: "none", caughtErrors: "none", varsIgnorePattern: "^_" }],
    },
  },
  {
    // Terminal protocol parsing deliberately recognizes escape/control bytes.
    files: ["tools/flow-reader/terminal/protocol.mjs", "tools/flow-reader/tests/test_terminal.mjs"],
    rules: { "no-control-regex": "off" },
  },
  {
    files: ["tools/typst-preview-frontend/src/**/*.{ts,mts}", "tools/typst-dom/src/**/*.{ts,mts}"],
    languageOptions: { parser: tsParser },
    plugins: { "@typescript-eslint": typescriptEslint },
    rules: {
      "no-undef": "off",
      "no-unused-vars": "off",
      "@typescript-eslint/no-unused-vars": [
        "error",
        { args: "none", caughtErrors: "none", varsIgnorePattern: "^_" },
      ],
      "no-redeclare": "off",
    },
  },
  {
    files: [
      "tools/reader-common/tests/*.mjs",
      "tools/flow-reader/tests/*.mjs",
      "tools/flow-reader/terminal/**/*.mjs",
      "tools/flow-reader/terminal.mjs",
      "tools/typst-preview-frontend/src/**/*.test.{ts,mts}",
      "tools/typst-dom/src/**/*.test.{ts,mts}",
    ],
    languageOptions: {
      globals: {
        ...Object.fromEntries(Object.keys(globals.browser).map((name) => [name, "off"])),
        ...globals.node,
      },
    },
  },
  {
    // These Node hosts also send callbacks to the browser through page.evaluate.
    files: [
      "tools/flow-reader/tests/*-browser.mjs",
      "tools/flow-reader/terminal/browser-session.mjs",
      "tools/flow-reader/terminal/editor-bridge.mjs",
      "tools/flow-reader/terminal/host.mjs",
    ],
    languageOptions: { globals: globals.browser },
  },
  ...compat
    .extends(
      "eslint:recommended",
      "plugin:@typescript-eslint/eslint-recommended",
      "plugin:@typescript-eslint/recommended",
      "plugin:@typescript-eslint/recommended-requiring-type-checking",
    )
    .map((config) => ({
      ...config,
      files: ["editors/vscode/**/*.ts"],
    })),
  {
    files: ["editors/vscode/**/*.ts"],

    plugins: {
      "@typescript-eslint": typescriptEslint,
    },

    languageOptions: {
      parser: tsParser,
      ecmaVersion: 10,
      sourceType: "module",

      parserOptions: {
        project: true,

        ecmaFeatures: {
          modules: true,
        },
      },
    },

    rules: {
      // "@typescript-eslint/member-delimiter-style": [
      //   "error",
      //   {
      //     multiline: {
      //       delimiter: "semi",
      //       requireLast: true,
      //     },

      //     singleline: {
      //       delimiter: "semi",
      //       requireLast: false,
      //     },
      //   },
      // ],

      semi: [2, "always"],

      "@typescript-eslint/no-inferrable-types": [
        "error",
        {
          ignoreParameters: true,
          ignoreProperties: true,
        },
      ],

      "no-unused-vars": "off",
      "@typescript-eslint/no-unused-vars": [
        "warn", // or "error"
        {
          argsIgnorePattern: "^_",
          varsIgnorePattern: "^_",
          caughtErrorsIgnorePattern: "^_",
        },
      ],

      "require-await": "off",
      "@typescript-eslint/require-await": 0,
      // todo: is it ok to disable this?
      "@typescript-eslint/restrict-template-expressions": 0,
      // todo: enable it in future
      "@typescript-eslint/no-misused-promises": 0,
      "@typescript-eslint/ban-ts-comment": 0,
      "@typescript-eslint/no-empty-function": 0,
      "@typescript-eslint/no-var-requires": 0,
      "@typescript-eslint/no-explicit-any": 0,
      "@typescript-eslint/no-floating-promises": 0,
      "@typescript-eslint/no-unsafe-assignment": 0,
      "@typescript-eslint/no-unsafe-return": 0,
      "@typescript-eslint/no-unsafe-call": 0,
      "@typescript-eslint/no-unsafe-member-access": 0,
      "@typescript-eslint/unbound-method": 0,
    },
  },
];
