```bash
#!/bin/bash

VENV_PATH="/path/to/your/venv"
HOST="127.0.0.1"
PORT="YOUR_API_PORT"

source "$VENV_PATH/bin/activate"

gunicorn -w 2 -k uvicorn.workers.UvicornWorker \
  --timeout 90 \
  -b "$HOST:$PORT" \
  --access-logfile - \
  --error-logfile - \
  api:app
```
