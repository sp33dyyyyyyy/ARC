'use strict';
// Curated recommendations. Sizes are approximate download sizes (Q4 quantised
// for Ollama). RAM figures are the realistic minimum system memory for the
// model plus OS/VIPER headroom. Speeds are rough ranges, shown as estimates.
const OLLAMA_RECOMMENDED = [
  { id: 'qwen2.5:0.5b', family: 'Qwen 2.5', params: '0.5B', sizeGB: 0.4, minRamGB: 4, roles: ['chat'], caps: ['chat', 'tools'], tier: 'tiny', note: 'Fastest. Fine for commands and short answers; weak reasoning.' },
  { id: 'llama3.2:1b', family: 'Llama 3.2', params: '1B', sizeGB: 1.3, minRamGB: 4, roles: ['chat'], caps: ['chat', 'tools'], tier: 'tiny', note: 'Very light general assistant.' },
  { id: 'llama3.2:3b', family: 'Llama 3.2', params: '3B', sizeGB: 2.0, minRamGB: 8, roles: ['chat'], caps: ['chat', 'tools'], tier: 'light', note: 'Good balance for 8 GB laptops.' },
  { id: 'qwen2.5:3b', family: 'Qwen 2.5', params: '3B', sizeGB: 1.9, minRamGB: 8, roles: ['chat'], caps: ['chat', 'tools'], tier: 'light', note: 'Recommended for laptops without a graphics card: fast, reliable tool calling.', rank: 3 },
  { id: 'phi4-mini', family: 'Phi-4 mini', params: '3.8B', sizeGB: 2.5, minRamGB: 8, roles: ['chat'], caps: ['chat', 'tools'], tier: 'light', note: 'Strong reasoning for its size.' },
  { id: 'qwen3:4b', family: 'Qwen 3', params: '4B', sizeGB: 2.6, minRamGB: 8, roles: ['chat'], caps: ['chat', 'tools'], tier: 'light', note: 'Hybrid thinking model; good tool use, but thinks before answering (slower first reply).', rank: -1 },
  { id: 'qwen2.5:7b', family: 'Qwen 2.5', params: '7B', sizeGB: 4.7, minRamGB: 16, roles: ['chat'], caps: ['chat', 'tools'], tier: 'standard', note: 'Recommended default for 16 GB PCs.' },
  { id: 'llama3.1:8b', family: 'Llama 3.1', params: '8B', sizeGB: 4.9, minRamGB: 16, roles: ['chat'], caps: ['chat', 'tools'], tier: 'standard', note: 'Well-rounded conversationalist.' },
  { id: 'qwen3:8b', family: 'Qwen 3', params: '8B', sizeGB: 5.2, minRamGB: 16, roles: ['chat'], caps: ['chat', 'tools'], tier: 'standard', note: 'Best general quality in the 8B class.' },
  { id: 'qwen2.5-coder:1.5b', family: 'Qwen 2.5 Coder', params: '1.5B', sizeGB: 1.0, minRamGB: 6, roles: ['code'], caps: ['chat', 'code', 'tools'], tier: 'light', note: 'Light coding assistant.' },
  { id: 'qwen2.5-coder:7b', family: 'Qwen 2.5 Coder', params: '7B', sizeGB: 4.7, minRamGB: 16, roles: ['code'], caps: ['chat', 'code', 'tools'], tier: 'standard', note: 'Strong local coding model.' },
  { id: 'moondream', family: 'Moondream 2', params: '1.8B', sizeGB: 1.7, minRamGB: 6, roles: ['vision'], caps: ['chat', 'vision'], tier: 'light', note: 'Light vision model: captions and simple questions.' },
  { id: 'qwen2.5vl:3b', family: 'Qwen 2.5 VL', params: '3B', sizeGB: 3.2, minRamGB: 10, roles: ['vision'], caps: ['chat', 'vision'], tier: 'standard', note: 'Reads text in screenshots well.', rank: 2 },
  { id: 'gemma3:4b', family: 'Gemma 3', params: '4B', sizeGB: 3.3, minRamGB: 10, roles: ['vision', 'chat'], caps: ['chat', 'vision'], tier: 'standard', note: 'Multimodal; good screenshot explanations.' },
  { id: 'llava:7b', family: 'LLaVA 1.6', params: '7B', sizeGB: 4.7, minRamGB: 16, roles: ['vision'], caps: ['chat', 'vision'], tier: 'standard', note: 'Classic vision-language model.' },
  { id: 'nomic-embed-text', family: 'Nomic Embed', params: '137M', sizeGB: 0.27, minRamGB: 2, roles: ['embeddings'], caps: ['embeddings'], tier: 'tiny', note: 'Embeddings for semantic file search.' },
  { id: 'all-minilm', family: 'MiniLM', params: '23M', sizeGB: 0.05, minRamGB: 1, roles: ['embeddings'], caps: ['embeddings'], tier: 'tiny', note: 'Tiny embeddings model.' },
];

// Foundry Local aliases (the service picks the CPU/GPU/NPU variant for the hardware).
const FOUNDRY_RECOMMENDED = [
  { id: 'qwen2.5-0.5b', family: 'Qwen 2.5', params: '0.5B', sizeGB: 0.8, minRamGB: 4, roles: ['chat'], tier: 'tiny', note: 'Fastest; basic answers.' },
  { id: 'qwen2.5-1.5b', family: 'Qwen 2.5', params: '1.5B', sizeGB: 1.8, minRamGB: 6, roles: ['chat'], tier: 'light', note: 'Light general model with tool calling.' },
  { id: 'phi-4-mini', family: 'Phi-4 mini', params: '3.8B', sizeGB: 3.6, minRamGB: 8, roles: ['chat'], tier: 'light', note: 'Recommended default on Foundry Local.', rank: 2 },
  { id: 'phi-3.5-mini', family: 'Phi-3.5 mini', params: '3.8B', sizeGB: 2.5, minRamGB: 8, roles: ['chat'], tier: 'light', note: 'Mature, efficient model.' },
  { id: 'qwen2.5-7b', family: 'Qwen 2.5', params: '7B', sizeGB: 5.0, minRamGB: 16, roles: ['chat'], tier: 'standard', note: 'Higher quality; best with a GPU/NPU.' },
  { id: 'qwen2.5-coder-1.5b', family: 'Qwen 2.5 Coder', params: '1.5B', sizeGB: 1.3, minRamGB: 6, roles: ['code'], tier: 'light', note: 'Light coding model.' },
  { id: 'qwen2.5-coder-7b', family: 'Qwen 2.5 Coder', params: '7B', sizeGB: 4.7, minRamGB: 16, roles: ['code'], tier: 'standard', note: 'Strong coding model.' },
  { id: 'deepseek-r1-7b', family: 'DeepSeek R1 distill', params: '7B', sizeGB: 5.6, minRamGB: 16, roles: ['chat'], tier: 'standard', note: 'Reasoning model (slower, verbose).', rank: -2 },
];

/** Recommend a configuration for detected hardware. */
function recommend(hw, backend = 'ollama') {
  const ram = hw?.ramGB || 8;
  const vram = hw?.gpu?.vramGB || 0;
  // 16 GB PCs report ~15.7 GB usable. Without a GPU, 7-8B models are too slow for
  // conversation (3-10 tok/s), so CPU-only machines below 32 GB get the light tier.
  let effective = Math.max(ram * 1.05, vram >= 6 ? 16 : 0);
  if (vram < 4 && ram < 32) effective = Math.min(effective, 15);
  const pick = (list, role) => {
    const fits = list.filter((m) => m.roles.includes(role) && m.minRamGB <= effective);
    const order = { tiny: 0, light: 1, standard: 2 };
    const tools = (m) => (role === 'chat' && m.caps && !m.caps.includes('tools') ? -1 : 0);
    fits.sort((a, b) => tools(b) - tools(a) || order[b.tier] - order[a.tier] || (b.rank || 0) - (a.rank || 0) || b.sizeGB - a.sizeGB);
    return fits[0] || list.filter((m) => m.roles.includes(role)).sort((a, b) => a.minRamGB - b.minRamGB)[0] || null;
  };
  const list = backend === 'foundry' ? FOUNDRY_RECOMMENDED : OLLAMA_RECOMMENDED;
  const chat = pick(list, 'chat');
  const tier = effective >= 16 ? 'standard' : effective >= 8 ? 'light' : 'tiny';
  const speed = {
    tiny: vram >= 4 ? '60–150 tokens/s (GPU)' : '20–60 tokens/s (CPU)',
    light: vram >= 4 ? '40–100 tokens/s (GPU)' : '8–25 tokens/s (CPU)',
    standard: vram >= 6 ? '30–80 tokens/s (GPU)' : '3–10 tokens/s (CPU, slow)',
  }[chat?.tier || tier];
  return {
    tier, backend,
    chat: chat?.id, code: pick(list, 'code')?.id,
    vision: backend === 'ollama' ? pick(OLLAMA_RECOMMENDED, 'vision')?.id : pick(OLLAMA_RECOMMENDED, 'vision')?.id,
    embeddings: 'nomic-embed-text',
    stt: ram >= 8 ? 'base.en' : 'tiny.en',
    expectedSpeed: speed,
    notes: [
      ram < 8 ? 'Less than 8 GB RAM detected: only tiny models will run comfortably. Close other apps before chatting.' : null,
      vram === 0 ? 'No dedicated GPU memory detected: inference will run on the CPU. Expect slower responses with larger models.' : null,
      vram >= 6 ? `GPU with ~${vram} GB VRAM detected: 7–8B models should run with GPU acceleration.` : null,
    ].filter(Boolean),
  };
}

module.exports = { OLLAMA_RECOMMENDED, FOUNDRY_RECOMMENDED, recommend };
