// app.js
const express = require('express');
const app = express();

app.use(express.json());

// /healthz
app.get('/healthz', (req, res) => {
  res.status(200).send('OK');
});

// Captura TODOS los métodos en /DevOps
app.all('/DevOps', (req, res) => {
  // 1. Rechazar métodos distintos a POST
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'ERROR' });
  }

  // 2. Validar que el body tenga los campos requeridos
  const { message, to, from, timeToLifeSec } = req.body;

  if (!message || !to || !from || timeToLifeSec === undefined) {
    return res.status(400).json({ error: 'ERROR' });
  }

  // 3. Respuesta válida
  return res.status(200).json({
    message: `Hello ${to} your message will be sent`
  });
});

app.listen(3000, () => console.log('Server running on port 3000'));



