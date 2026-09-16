# Environment Configuration

Rule sources:

- [`environment_configuration.mdc`](../../.cursor/environment_configuration.mdc)
- [`security.mdc`](../../.cursor/security.mdc)
- [`network_api.mdc`](../../.cursor/network_api.mdc)
- [`feature_flags.mdc`](../../.cursor/feature_flags.mdc)

The app reads public, non-secret configuration from Flutter compile-time
defines. Store environment-specific values in Flutter define files under
`env/` and pass them with `--dart-define-from-file`. The repository commits
only `.json.example` define files. Copy an example to an ignored `env/*.json`
file when local or CI values need to differ. Do not commit secrets, tokens,
passwords, private certificates, or API keys in source code, docs, assets, or
local environment files.

## Files

| File | Purpose |
|---|---|
| `env/development.json.example` | Local development starter values. |
| `env/staging.json.example` | Staging placeholder values. |
| `env/production.json.example` | Production-safe placeholder values for release smoke builds. |

Use ignored `env/*.json` or `env/*.local.json` files for machine-specific
overrides.

## Values

| Key | Required | Values | Default |
|---|---:|---|---|
| `APP_ENV` | Yes | `development`, `staging`, `production` | none |
| `API_BASE_URL` | Yes | Absolute `http` or `https` URL | none |
| `API_TIMEOUT_SECONDS` | No | Positive integer seconds | `30` |
| `LOG_LEVEL` | No | `debug`, `info`, `warn`, `error` | `info` |
| `FEATURE_DEVELOPER_TOOLS_ENABLED` | No | `true`, `false` | `false` |
| `APP_VERSION` | No | Running build as `version+build`, e.g. `0.1.0+1` | none |

`APP_VERSION` is not kept in the define files. `deploy/update-deploys/frontend.py`
and `android.py` pass `--dart-define=APP_VERSION=<version>` from the
`pubspec.yaml` `version:` line, so submitted feedback records the build it came
from. Other builds send no app version unless given the define.

Production `API_BASE_URL` values must use `https`. URLs must not include
usernames, passwords, tokens, or other credentials.

## Examples

Development can use a local HTTP endpoint:

```sh
flutter run -d chrome --web-hostname=127.0.0.1 --web-port=5201 --dart-define-from-file=env/development.json.example --no-web-enable-expression-evaluation --no-web-resources-cdn
```

Staging and production should use public HTTPS endpoints:

```sh
flutter run -d chrome --dart-define-from-file=env/staging.json.example --no-web-enable-expression-evaluation --no-web-resources-cdn
```

```sh
flutter build web --release --no-web-resources-cdn --dart-define-from-file=env/production.json.example
```

Command-line `--dart-define=KEY=value` entries can still be used for CI or
temporary overrides; Flutter gives them precedence over matching keys from
define files.

## Tests

Tests should override `appConfigProvider` with a purpose-built `AppConfig`
instead of relying on process-level compile-time values. This keeps tests
isolated and prevents accidental dependency on local machine settings.
