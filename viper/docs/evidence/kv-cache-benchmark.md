# Prompt-cache benchmark (real model)

Ollama 0.40.16, qwen2.5:0.5b (Q4_K_M), Linux container with 4 vCPU and no GPU. Four-turn
conversation through VIPER's orchestrator, with the clock advanced 70 s between messages.
Requests mix tool needs (file search, reminders). TTFT means time to first token.

| Turn | Before: TTFT | After: TTFT | After: prompt eval |
|---|---|---|---|
| 1 "Explain what RAM is" | 5,599 ms | 455 ms* | 396 ms |
| 2 "search my files…" | 5,083 ms | 2,158 ms | 2,127 ms |
| 3 "remember to restart…" | 4,881 ms | 1,227 ms | 1,202 ms |
| 4 "Summarise our chat" | 4,642 ms | 1,417 ms | 1,390 ms |

\*Turn 1 reused the static prefix that was already cached in the engine from the previous
session. Start-up warm-up gives the same effect. With a cold engine, turn 1 measured 4,975 ms.

**Cause before:** the system prompt contained the current minute and the memories retrieved for
each query. The tool list was also re-ranked per query. Each of these changed the prompt
prefix, so the engine re-processed the system prompt and all tool definitions on every turn.

**Fix:** the system prompt and base tools are now static and in a fixed order. Request-specific
tools are appended after them. Time, memories and device context go in a `[Context]` block on
the current user message. The chat model is also warmed with the static prefix.
