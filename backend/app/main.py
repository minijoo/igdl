import logging
import os

from fastapi import Depends, FastAPI, Header, HTTPException

from . import instagram

# uvicorn only configures its own "uvicorn"/"uvicorn.access"/"uvicorn.error"
# loggers — without this, instagram.py's "igdl.resolve" logger has no
# handler anywhere in its chain and its records are silently dropped. This
# attaches one to the root logger, which is what journald actually captures
# (the systemd unit's StandardOutput/StandardError are both `journal`).
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(name)s %(levelname)s %(message)s')

app = FastAPI(title='IGDL Backend')


def require_api_key(x_api_key: str = Header(default='')) -> None:
    expected = os.environ.get('IGDL_API_KEY')
    if not expected:
        # Fails closed: a server with no key configured refuses everything,
        # rather than silently running open once this is deployed publicly.
        raise HTTPException(500, 'server missing IGDL_API_KEY')
    if x_api_key != expected:
        raise HTTPException(401, 'invalid or missing API key')


@app.get('/downloads/resolve', dependencies=[Depends(require_api_key)])
def resolve_download(short_code: str):
    try:
        return instagram.resolve_post(short_code)
    except instagram.ResolveError as e:
        raise HTTPException(502, str(e))
