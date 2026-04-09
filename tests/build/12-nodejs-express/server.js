const express = require('express');
const app = express();
const port = 3000;

app.get('/', (req, res) => {
  // Simulate some work
  let sum = 0;
  for (let i = 0; i < 1000000; i++) {
    sum += Math.random();
  }
  res.json({ status: 'ok', sum: sum });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.listen(port, '0.0.0.0', () => {
  console.log(`Express server listening on port ${port}`);
});
