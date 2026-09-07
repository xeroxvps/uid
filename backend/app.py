from fastapi import FastAPI

app = FastAPI(title="Xerox UID v2")

@app.get("/")
def health():
    return {"status": "running", "project": "Xerox UID v2"}
