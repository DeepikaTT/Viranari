import os
import uvicorn

if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host=os.getenv("VIRANARI_HOST", "0.0.0.0"),
        port=int(os.getenv("VIRANARI_PORT", "3000")),
        reload=os.getenv("VIRANARI_RELOAD", "0") == "1",
    )
