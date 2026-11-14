# Writing VIPER plugins

A plugin is a folder (or .zip) with `plugin.json` and a JavaScript entry file. It runs in a
QuickJS WebAssembly sandbox: no `require`, no `process`, no filesystem, no network except through
the host API, 32 MB memory, and calls are interrupted after 20 s.

```json
{
  "id": "acme.weather",
  "name": "Weather",
  "version": "1.0.0",
  "description": "Current weather tool and widget.",
  "main": "main.js",
  "permissions": ["http:api.open-meteo.com", "storage"],
  "contributes": {
    "tools": [{ "name": "weather_now", "description": "Current weather for a city", "risk": "read",
                "parameters": { "type": "object", "properties": { "city": { "type": "string" } }, "required": ["city"] } }],
    "widgets": [{ "id": "today", "title": "Weather" }],
    "pages": [{ "id": "forecast", "title": "Forecast" }],
    "actions": [{ "id": "post", "label": "Post weather to the notification feed" }],
    "notificationChannels": [{ "id": "webhook", "label": "My webhook" }],
    "documentReaders": [{ "id": "log2", "extensions": ["log2"] }],
    "models": [{ "id": "lmstudio", "label": "LM Studio", "baseUrl": "http://127.0.0.1:1234/v1" }]
  }
}
```

```js
plugin.tools.weather_now = async ({ city }) => {
  const r = await viper.http(`https://api.open-meteo.com/v1/forecast?...`);
  return JSON.parse(r.text).current;
};
plugin.widgets.today = async () => ({ title: 'Weather', lines: ['London 14°C'] });
plugin.pages.forecast = async (input) => ({ markdown: '…', input: { placeholder: 'City' } });
plugin.actions.post = async (args) => ({ ok: true });
plugin.notify.webhook = async ({ title, body }) => ({ ok: true });
plugin.readers.log2 = async ({ text }) => text;
```

Host API: `viper.log`, `viper.http(url, {method, headers, body})` (HTTPS only, hosts listed as
`http:<host>`), `viper.storage.get/set` (`storage`), `viper.notify(title, body)` (`notify`),
`viper.system()` (`system.read`), `viper.ask(prompt)` (`ai`, local model). Model endpoints must be
on 127.0.0.1.

The user grants permissions per plugin at install time and can revoke them later. Plugin tools use
the `plugin.tools` permission category (default: Ask) and their output is treated as untrusted.
See `desktop/plugins-examples/viper-utilities`.
