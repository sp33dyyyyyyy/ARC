'use strict';
// Headless VIPER core: `npm run server`. Useful for servers, testing and
// running the UI in any browser on this machine.
const { createViper } = require('./server');

(async () => {
  const port = process.env.VIPER_PORT ? Number(process.env.VIPER_PORT) : undefined;
  const svc = await createViper({ echoLogs: !!process.env.VIPER_ECHO, port, token: process.env.VIPER_TOKEN, dataDir: process.env.VIPER_DATA_DIR });
  console.log(`\n  VIPER core online.\n  Open: ${svc.url}/?token=${svc.localToken}\n  Data: ${svc.paths.data}\n`);
  const stop = async () => { await svc.shutdown(); process.exit(0); };
  process.on('SIGINT', stop); process.on('SIGTERM', stop);
})().catch((e) => { console.error('VIPER failed to start:', e); process.exit(1); });
