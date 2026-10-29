# AI configuration

In the app, open **Read → Settings → AI service**. Select the format, enter the complete HTTPS endpoint, model name and optional API key, then save. Coach, AI dictionary lookup and translation all resolve this configuration. No service is enabled until configured.

The API key is kept in Keychain using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; it is excluded from UserDefaults and does not sync through this app. Endpoint, model and format are stored in UserDefaults. Removing AI configuration also removes its Keychain item. Clearing learning data retains AI configuration; use **Remove AI configuration** to remove it separately.

The endpoint is used exactly as entered, including its path and query. No automatic path suffix is added. HTTPS URLs with embedded credentials or fragments are rejected. The app does not insert a provider key or installation identifier of its own. A configured key is sent as `Authorization: Bearer …`.

## Supported formats

| Setting | Example full endpoint | Request | Non-stream response |
| --- | --- | --- | --- |
| Responses | `https://api.openai.com/v1/responses` | `model`, `input: [{role, content}]`, `stream`, `store: false` | Completed response `output[].content[]` items of type `output_text` |
| Chat Completions | `https://api.openai.com/v1/chat/completions` | `model`, `messages: [{role, content}]`, `stream` | `choices[0].message.content` |
| Custom relay | `https://your-service.example/api/ai/chat` | `messages: [{role, content}]`, `stream`; optional `model` | `{ "text": "…" }` |

Model is required for Responses and Chat Completions, optional for the relay. These are remote text interfaces; this implementation does not execute tool calls, generate images or load local MLX models.

**Test connection** sends two short requests using the current draft: one completion and one stream. It can incur usage charges. It reports success only if both paths work and does not save the draft. Requests to real providers require the user's own service configuration and credentials.

## Streaming

All formats use `Content-Type: text/event-stream`. SSE framing handles CRLF/LF/CR, network chunk boundaries, UTF-8, comments and multiline data. A single event is bounded to 1 MiB.

Responses recognizes `response.output_text.delta`, `response.output_text.done`, `response.completed`, `response.failed`, `response.incomplete` and error events. Text from `.done` is a fallback when that output part did not emit deltas. A complete terminal response can supply text when no deltas were sent. Reasoning events are ignored. Successful completion requires `response.completed` with completed status and nonempty text; no `[DONE]` marker is required. An unexpected `[DONE]` cannot substitute for the Responses completion event.

Chat Completions and the relay use `choices[0].delta.content` and terminate with `[DONE]`. An interrupted connection, malformed data or a failure event throws instead of turning a partial reply into success. Coach persists a reply only after successful stream completion.

## Failure and cancellation

HTTP 401/403 reports a credentials issue; 429 reports capacity/quota; offline, invalid configuration, protocol failure and interruption have distinct errors. Raw provider error bodies and keys are not displayed or logged. Task cancellation is preserved as cancellation and propagates to URLSession. Configuration revisions and data-generation checkpoints prevent an old result from being committed after configuration changes or data clearing.

## Implementation

- `AIConfiguration.swift`: validated configuration, Keychain adapter and configuration persistence.
- `AISettingsView.swift`: draft editing, connection test, save and removal.
- `AIClient.swift`: injectable URLSession adapter and non-stream response decoding.
- `AIStreamParser.swift`: Responses and Chat Completions event decoding.
- `AI.swift`: shared feature entry point, cancellation/error mapping and translation prompts.
- `ServerSentEvents.swift`: bounded transport framing independent of provider JSON.
- `CoachSession.swift`: conversation state, correction tasks, cancellation and persistence.

A public relay remains responsible for authentication, request limits and budgets. Chat, selected reading passages and saved vocabulary may be sent to the selected service. `store: false` is a request setting, not a claim about a provider's entire retention policy.
