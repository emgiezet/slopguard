# AP-PY-PERF-002 — Blocking calls inside async functions

**Category:** performance | **Severity:** error
**Frameworks:** [plain, fastapi, aiohttp]

## Summary
Calling `requests.get`, `time.sleep`, or synchronous file I/O inside an `async def` blocks the entire event loop, negating the benefits of async. Replace with `httpx.AsyncClient`, `asyncio.sleep`, and `aiofiles`.

## Do Not Write
```python
async def fetch_data():
    resp = requests.get("https://api.example.com")   # blocks event loop
```

## Instead Write
```python
async def fetch_data():
    async with httpx.AsyncClient() as client:
        resp = await client.get("https://api.example.com", timeout=10)
```

## Detection
- ruff: `ASYNC100`
- ruff: `ASYNC110`
- ruff: `ASYNC210`
- ruff: `ASYNC220`

