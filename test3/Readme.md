Claude Celula Lab

** Aplicación - Node.js con Express **

// app.js
const express = require('express');
const app = express();

app.use(express.json());

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

Para ejecutarlo:
npm init -y
npm install express
node app.js

Cómo probarlo (con curl)
Caso exitoso:
curl -X POST http://localhost:3000/DevOps \
  -H "Content-Type: application/json" \
  -d '{"message":"This is a test","to":"Juan Perez","from":"Rita Asturia","timeToLifeSec":45}'
# → {"message":"Hello Juan Perez your message will be sent"}

Método incorrecto (GET):
curl -X GET http://localhost:3000/DevOps
# → {"error":"ERROR"}

Body inválido (campo faltante):
curl -X POST http://localhost:3000/DevOps \
  -H "Content-Type: application/json" \
  -d '{"message":"test"}'
# → {"error":"ERROR"}

Lógica clave (resumen)
La solución tiene tres pasos en orden:

Verificar el método HTTP — si no es POST, devolver {"error":"ERROR"} inmediatamente.
Validar el body — deben existir los 4 campos: message, to, from, timeToLifeSec. Si falta alguno o el JSON es inválido, devolver {"error":"ERROR"}.
Construir la respuesta — usar el campo to del body para armar "Hello {to} your message will be sent".


** Docker **

Archivos que necesitas crear
Tu proyecto debe verse así:

mi-proyecto/
│
├── app.js              ← tu código (ya lo tienes)
├── package.json        ← lista de ingredientes
├── Dockerfile          ← instrucciones para armar la cajita
└── .dockerignore       ← cosas que NO van en la cajita

Paso 1 — El package.json

{
  "name": "devops-microservice",
  "version": "1.0.0",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}


Paso 2 — El Dockerfile

# 1. ¿En qué base nos paramos?
FROM node:18-alpine

# 2. ¿Dónde trabajamos dentro de la cajita?
WORKDIR /app

# 3. Copiar la lista de ingredientes primero
COPY package.json .

# 4. Instalar los ingredientes
RUN npm install

# 5. Copiar el resto del código
COPY . .

# 6. Decirle a Docker que la app usa el puerto 3000
EXPOSE 3000

# 7. El comando para arrancar la app
CMD ["node", "app.js"]


Paso 4 - Docker build

docker build -t mi-devops-app .
```

- `docker build` → *"construye la cajita"*
- `-t mi-devops-app` → *"ponle ese nombre a la cajita"* (t = tag = etiqueta)
- `.` → *"usa el Dockerfile que está aquí mismo"*


Paso 5 - Docker build

docker run -p 3000:3000 mi-devops-app
```

- `docker run` → *"abre y enciende la cajita"*
- `-p 3000:3000` → *"conecta el puerto 3000 de tu computadora con el puerto 3000 de la cajita"*
- `mi-devops-app` → *"esa cajita que construimos"*

Prueba

curl -X POST http://localhost:3000/DevOps \
  -H "Content-Type: application/json" \
  -d '{"message":"This is a test","to":"Juan Perez","from":"Rita Asturia","timeToLifeSec":45}'


** AKS **

Herramientas que necesitas instalar
1. Azure CLI 
2. kubectl — az aks install-cli
3. Docker Desktop

PASO 1 — Iniciar sesión en Azure 
az login

PASO 2
az group create \
  --name mi-grupo-devops \
  --location eastus

PASO 3
az acr create \
  --resource-group mi-grupo-devops \
  --name miregistrodevops \
  --sku Basic

Ahora inicia sesión en esa bodega:
az acr login --name miregistrodevops  

PASO 4 - subir imagen
Etiquetar imagen
docker build -t miregistrodevops.azurecr.io/devops-app:v1 .
Subir imagen
docker push miregistrodevops.azurecr.io/devops-app:v1

Paso 5 - Crea AKS
az aks create \
  --resource-group mi-grupo-devops \
  --name mi-cluster-devops \
  --node-count 1 \
  --attach-acr miregistrodevops \
  --generate-ssh-keys

Paso 6 - Conectar AKS
az aks get-credentials \
  --resource-group mi-grupo-devops \
  --name mi-cluster-devops

kubectl get nodes

PASO 7 — Crear los archivos de Kubernetes
Archivo 1: deployment.yaml 
apiVersion: apps/v1
kind: Deployment
metadata:
  name: devops-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: devops-app
  template:
    metadata:
      labels:
        app: devops-app
    spec:
      containers:
        - name: devops-app
          image: miregistrodevops.azurecr.io/devops-app:v1
          ports:
            - containerPort: 3000

Archivo 2: service.yaml
apiVersion: v1
kind: Service
metadata:
  name: devops-service
spec:
  type: LoadBalancer
  selector:
    app: devops-app
  ports:
    - port: 80
      targetPort: 3000


PASO 8 — Desplegar todo
# Aplicar el deployment
kubectl apply -f deployment.yaml

# Aplicar el service
kubectl apply -f service.yaml

kubectl get pods


PASO 9 — Obtener la IP pública
kubectl get service devops-service

PASO 10 — Probarlo
curl -X POST http://20.85.124.33/DevOps \
  -H "Content-Type: application/json" \
  -d '{"message":"This is a test","to":"Juan Perez","from":"Rita Asturia","timeToLifeSec":45}'


Comandos del día a día 🛠️
kubectl get pods
kubectl get services Ver la IP pública
kubectl logs <nombre-pod>Ver qué imprime tu app
kubectl scale deployment devops-app --replicas=3 
kubectl delete -f deployment.yaml

# Apagar el cluster (pero no borrarlo)
az aks stop --name mi-cluster-devops --resource-group mi-grupo-devops
# O borrar todo si ya no lo necesitas
az group delete --name mi-grupo-devops --yes


