const express = require('express')
const app = express()
const PORT = Number(process.env.PORT) || 3000

// Version del codigo, se puede injectar como variable de entorno en un caso real
const APP_VERSION = '1.0.0'

app.get('/', (req, res) => {
  const version = process.env.APP_VERSION || APP_VERSION
  const bgColor = process.env.APP_COLOR || 'white'
  const textColor = process.env.APP_COLOR === 'blue' ? 'white' : 'black'

  res.send(`
    <body style="background-color: ${bgColor}; color: ${textColor}; font-family: sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0;">
      <div style="text-align: center;">
        <h1>¡Hola Mundo!</h1>
        <h2>Versión: ${version}</h2>
        <h3>Color del Entorno: ${process.env.APP_COLOR || 'N/A'}</h3>
        <p style="font-size:0.9em;opacity:0.8;">Stack: <span id="stack">${process.env.DEPLOYMENT_COLOR || 'N/A'}</span></p>
      </div>
      <script>
        (function(){
          var last = '${process.env.DEPLOYMENT_COLOR || ''}';
          function check() {
            fetch('/api/deploy-id', { cache: 'no-cache' }).then(function(r){ return r.json(); }).then(function(d){
              if (d.stack && d.stack !== last) { last = d.stack; location.reload(); }
            }).catch(function(){});
          }
          setInterval(check, 15000);
          document.addEventListener('visibilitychange', function(){ if (document.visibilityState === 'visible') check(); });
        })();
      </script>
    </body>
  `)
})

app.get('/health', (req, res) => {
  res.status(200).send('OK')
})

// Endpoint barato para detectar en qué stack estás (blue/green). Cache corto: al hacer switch
// el cliente revalida y ve el cambio, entonces puede invalidar su caché o recargar.
const STACK = process.env.DEPLOYMENT_COLOR || 'unknown'
app.get('/api/deploy-id', (req, res) => {
  res.set('Cache-Control', 'no-cache, must-revalidate')
  res.set('Connection', 'close')
  res.json({ stack: STACK, deployId: STACK })
})

app.listen(PORT, () => {
  console.log(`App listening on port ${PORT}`)
})
